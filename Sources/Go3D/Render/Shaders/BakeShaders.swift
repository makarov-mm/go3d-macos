extension ShaderSource {
    /// Compute kernels that bake the light probes: the studio environment, its irradiance, its prefiltered levels for
    /// each roughness, and the split-sum BRDF table.
    static let bake = #"""
    // Laid out as EnvironmentParams in RenderTypes.swift.
    struct EnvironmentParams {
        float4 ceilingColor;
        float4 horizonColor;
        float4 floorColor;
        uint4 counts; // x: the number of panels
    };

    // The studio: a backdrop graded from the floor to the ceiling, and soft boxes and light strips round the board.
    kernel void environmentKernel(texturecube<float, access::write> output [[texture(0)]],
                                  constant EnvironmentParams& params [[buffer(0)]],
                                  constant float4* panelDirection [[buffer(1)]], // xyz toward the panel, w: roll
                                  constant float4* panelShape [[buffer(2)]],     // half width, half height (as tangents), corner, softness
                                  constant float4* panelColor [[buffer(3)]],     // rgb radiance, w: falloff from the center
                                  uint3 gid [[thread_position_in_grid]])
    {
        uint size = output.get_width();
        if (gid.x >= size || gid.y >= size)
            return;
        float3 d = CubeDirection(gid, float(size));
        float3 color = d.y > 0.0 ? mix(params.horizonColor.rgb, params.ceilingColor.rgb, float3(pow(d.y, 0.55)))
                                 : mix(params.horizonColor.rgb, params.floorColor.rgb, float3(pow(-d.y, 0.35)));
        for (uint i = 0; i < params.counts.x; ++i) {
            float3 center = normalize(panelDirection[i].xyz);
            float facing = dot(d, center);
            if (facing <= 0.05)
                continue;
            float3x3 frame = TangentFrame(center);
            float2 q = float2(dot(d, frame[0]), dot(d, frame[1])) / facing;
            float roll = panelDirection[i].w;
            q = float2x2(float2(cos(roll), sin(roll)), float2(-sin(roll), cos(roll))) * q;
            float4 shape = panelShape[i];
            float sdf = RoundedBox(q, shape.xy, shape.z);
            float mask = 1.0 - smoothstep(-shape.w, shape.w, sdf);
            float falloff = 1.0 - panelColor[i].w * clamp(length(q / shape.xy) * 0.7, 0.0, 1.0);
            color += panelColor[i].rgb * mask * falloff;
        }
        output.write(float4(color, 1.0), gid.xy, gid.z);
    }

    // The light falling on a matte surface facing each direction: the environment averaged over a cosine.
    kernel void irradianceKernel(texturecube<float> environment [[texture(0)]],
                                 texturecube<float, access::write> output [[texture(1)]],
                                 constant float4& params [[buffer(0)]], // x: the level of the environment read
                                 uint3 gid [[thread_position_in_grid]])
    {
        uint size = output.get_width();
        if (gid.x >= size || gid.y >= size)
            return;
        float3 n = CubeDirection(gid, float(size));
        float3x3 frame = TangentFrame(n);
        const uint count = 1024;
        float3 sum = float3(0.0);
        for (uint i = 0; i < count; ++i) {
            float2 xi = Hammersley(i, count);
            float phi = 2.0 * Pi * xi.x;
            float cosTheta = sqrt(1.0 - xi.y);
            float sinTheta = sqrt(xi.y);
            float3 direction = frame * float3(sinTheta * cos(phi), sinTheta * sin(phi), cosTheta);
            sum += environment.sample(linearClamp, direction, level(params.x)).rgb;
        }
        output.write(float4(sum / float(count), 1.0), gid.xy, gid.z);
    }

    // The environment blurred for one roughness, by importance sampling the GGX lobe.
    kernel void prefilterKernel(texturecube<float> environment [[texture(0)]],
                                texturecube<float, access::write> output [[texture(1)]],
                                constant float4& params [[buffer(0)]], // x: roughness, y: the size of the environment
                                uint3 gid [[thread_position_in_grid]])
    {
        uint size = output.get_width();
        if (gid.x >= size || gid.y >= size)
            return;
        float roughness = params.x;
        float3 n = CubeDirection(gid, float(size));
        if (roughness <= 0.0) {
            output.write(float4(environment.sample(linearClamp, n, level(0.0)).rgb, 1.0), gid.xy, gid.z);
            return;
        }

        float3x3 frame = TangentFrame(n);
        const uint count = 512;
        float texelSolidAngle = 4.0 * Pi / (6.0 * params.y * params.y);
        float3 sum = float3(0.0);
        float weights = 0.0;
        for (uint i = 0; i < count; ++i) {
            float3 h = frame * ImportanceSampleGgx(Hammersley(i, count), roughness);
            float3 l = reflect(-n, h);
            float NoL = dot(n, l);
            if (NoL <= 0.0)
                continue;
            // Sparse samples read a blurrier level, so bright spots spread instead of sparkling.
            float NoH = max(dot(n, h), 0.0);
            float pdf = DistributionGgx(NoH, roughness) * 0.25 + 1e-4;
            float sampleSolidAngle = 1.0 / (float(count) * pdf);
            float lod = max(0.5 * log2(sampleSolidAngle / texelSolidAngle) + 1.0, 0.0);
            sum += environment.sample(linearClamp, l, level(lod)).rgb * NoL;
            weights += NoL;
        }
        output.write(float4(sum / max(weights, 1e-4), 1.0), gid.xy, gid.z);
    }

    float GeometrySchlickGgx(float NoX, float roughness)
    {
        float k = roughness * roughness / 2.0;
        return NoX / (NoX * (1.0 - k) + k);
    }

    // The split-sum lookup table: the scale and bias that turn F0 into the reflected share of the environment.
    kernel void brdfKernel(texture2d<float, access::write> output [[texture(0)]], uint3 gid [[thread_position_in_grid]])
    {
        uint2 size = uint2(output.get_width(), output.get_height());
        if (gid.x >= size.x || gid.y >= size.y)
            return;
        float NoV = max((float(gid.x) + 0.5) / float(size.x), 1e-3);
        float roughness = (float(gid.y) + 0.5) / float(size.y);
        float3 v = float3(sqrt(1.0 - NoV * NoV), 0.0, NoV);

        const uint count = 1024;
        float scale = 0.0, bias = 0.0;
        for (uint i = 0; i < count; ++i) {
            float3 h = ImportanceSampleGgx(Hammersley(i, count), roughness);
            float3 l = normalize(2.0 * dot(v, h) * h - v);
            float NoL = max(l.z, 0.0);
            float NoH = max(h.z, 0.0);
            float VoH = max(dot(v, h), 0.0);
            if (NoL > 0.0) {
                float g = GeometrySchlickGgx(NoV, roughness) * GeometrySchlickGgx(NoL, roughness);
                float visibility = g * VoH / max(NoH * NoV, 1e-4);
                float fresnel = pow(1.0 - VoH, 5.0);
                scale += (1.0 - fresnel) * visibility;
                bias += fresnel * visibility;
            }
        }
        output.write(float4(scale / float(count), bias / float(count), 0.0, 0.0), gid.xy);
    }
    """#
}

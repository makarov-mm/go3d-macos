extension ShaderSource {
    /// Physically based shading: a key light with soft shadows, and image-based light from a studio.
    static let lighting = #"""
    struct Material {
        float3 albedo;
        float roughness;
        float metallic;
        float clearcoat;
        float clearcoatRoughness;
        float subsurface; // light wrapping round, for ivory and porcelain
        float occlusion;
        float3 emissive;
        float4 reflection; // a planar reflection that replaces the environment: rgb, weight
    };

    Material DefaultMaterial(float3 albedo, float roughness)
    {
        Material m;
        m.albedo = albedo;
        m.roughness = roughness;
        m.metallic = 0.0;
        m.clearcoat = 0.0;
        m.clearcoatRoughness = 0.05;
        m.subsurface = 0.0;
        m.occlusion = 1.0;
        m.emissive = float3(0.0);
        m.reflection = float4(0.0);
        return m;
    }

    // How much the normal turns within the pixel. Highlights are widened by it, so that they do not sparkle on curved
    // and bevelled edges (specular anti-aliasing, after Tokuyoshi and Kaplanyan). To be called where all the pixels
    // of a quad take the same path.
    float NormalSpread(float3 N)
    {
        float3 dx = dfdx(N), dy = dfdy(N);
        return min(0.5 * (dot(dx, dx) + dot(dy, dy)), 0.18);
    }

    float WidenRoughness(float roughness, float spread)
    {
        float a = roughness * roughness;
        return sqrt(sqrt(saturate(a * a + spread)));
    }

    float VisibilitySmithGgx(float NoV, float NoL, float roughness)
    {
        float a = roughness * roughness;
        float a2 = a * a;
        float lambdaV = NoL * sqrt(NoV * NoV * (1.0 - a2) + a2);
        float lambdaL = NoV * sqrt(NoL * NoL * (1.0 - a2) + a2);
        return 0.5 / max(lambdaV + lambdaL, 1e-5);
    }

    float3 FresnelSchlick3(float3 f0, float cosine)
    {
        return f0 + (1.0 - f0) * pow(1.0 - cosine, 5.0);
    }

    float FresnelSchlick1(float f0, float cosine)
    {
        return f0 + (1.0 - f0) * pow(1.0 - cosine, 5.0);
    }

    float3 FresnelRoughness(float3 f0, float NoV, float roughness)
    {
        return f0 + (max(float3(1.0 - roughness), f0) - f0) * pow(1.0 - NoV, 5.0);
    }

    float SpecularOcclusion(float NoV, float occlusion, float roughness)
    {
        return saturate(pow(NoV + occlusion, exp2(-16.0 * roughness - 1.0)) - 1.0 + occlusion);
    }

    constant float2 Poisson[16] = {
        float2(-0.94201624, -0.39906216), float2(0.94558609, -0.76890725), float2(-0.09418410, -0.92938870), float2(0.34495938, 0.29387760),
        float2(-0.91588581, 0.45771432), float2(-0.81544232, -0.87912464), float2(-0.38277543, 0.27676845), float2(0.97484398, 0.75648379),
        float2(0.44323325, -0.97511554), float2(0.53742981, -0.47373420), float2(-0.26496911, -0.41893023), float2(0.79197514, 0.19090188),
        float2(-0.24188840, 0.99706507), float2(-0.81409955, 0.91437590), float2(0.19984126, 0.78641367), float2(0.14383161, -0.14100790)
    };

    // Percentage-closer soft shadows: the penumbra widens with the distance from the shadow's caster. `pixel` is the
    // fragment's position on the screen, for the rotation of the sample pattern.
    float Shadow(float3 position, float3 normal, float2 pixel, constant FrameData& frame, depth2d<float> shadowMap)
    {
        float texel = frame.lightDirection.w;
        float3 offsetPosition = position + normal * texel * 1.5;
        float4 light = frame.lightViewProjection * float4(offsetPosition, 1.0);
        float3 ndc = light.xyz / light.w;
        float2 uv = float2(ndc.x * 0.5 + 0.5, 0.5 - ndc.y * 0.5);
        float depth = ndc.z;
        if (uv.x <= 0.0 || uv.x >= 1.0 || uv.y <= 0.0 || uv.y >= 1.0 || depth >= 1.0)
            return 1.0;

        float angle = 6.2831853 * InterleavedGradientNoise(pixel);
        float2x2 rotation = float2x2(float2(cos(angle), sin(angle)), float2(-sin(angle), cos(angle)));
        float2 texelUv = 1.0 / float2(float(shadowMap.get_width()), float(shadowMap.get_height()));
        float bias = frame.shadowParams.y;

        float blockerSum = 0.0;
        float blockers = 0.0;
        for (int i = 0; i < 12; ++i) {
            float blocker = shadowMap.sample(nearestClamp, uv + rotation * Poisson[i] * 14.0 * texelUv);
            if (blocker < depth - bias) {
                blockerSum += blocker;
                blockers += 1.0;
            }
        }
        if (blockers == 0.0)
            return 1.0;

        float casterDistance = (depth - blockerSum / blockers) * frame.shadowParams.x;
        float penumbra = clamp(casterDistance * frame.lightColor.w / texel, 1.2, 16.0);
        float lit = 0.0;
        for (int i = 0; i < 16; ++i)
            lit += shadowMap.sample_compare(shadowCompare, uv + rotation * Poisson[i] * penumbra * texelUv, depth - bias);
        return lit / 16.0;
    }

    float3 Shade(Material m, float3 position, float3 N, float3 V, float shadow, constant FrameData& frame,
                 texturecube<float> irradiance, texturecube<float> prefiltered, texture2d<float> brdf)
    {
        float NoV = max(dot(N, V), 1e-4);
        float3 f0 = mix(float3(0.04), m.albedo, float3(m.metallic));
        float3 diffuseColor = m.albedo * (1.0 - m.metallic);

        // The key light.
        float3 L = frame.lightDirection.xyz;
        float3 H = normalize(V + L);
        float NoL = dot(N, L);
        float NoLc = saturate(NoL);
        float NoH = saturate(dot(N, H));
        float VoH = saturate(dot(V, H));
        float wrap = m.subsurface * 0.5;
        float diffuseLight = saturate((NoL + wrap) / ((1.0 + wrap) * (1.0 + wrap)));
        float3 F = FresnelSchlick3(f0, VoH);
        float3 specular = DistributionGgx(NoH, m.roughness) * VisibilitySmithGgx(NoV, NoLc, m.roughness) * F * NoLc;
        float3 diffuse = diffuseColor / Pi * diffuseLight * (1.0 - F);
        // Light passing through thin parts, warmed by the material.
        diffuse += diffuseColor * m.subsurface * 0.12 * pow(saturate(dot(V, -L)), 3.0);
        float3 direct = (diffuse + specular) * frame.lightColor.rgb * shadow;

        if (m.clearcoat > 0.0) {
            float coat = FresnelSchlick1(0.04, VoH) * m.clearcoat;
            float coatSpecular = DistributionGgx(NoH, m.clearcoatRoughness) * 0.25 / max(VoH * VoH, 1e-4);
            direct = direct * (1.0 - coat) + coat * coatSpecular * NoLc * frame.lightColor.rgb * shadow;
        }

        // The studio around.
        float3 R = reflect(-V, N);
        float2 split = brdf.sample(linearClamp, float2(NoV, m.roughness)).rg;
        float3 Fr = FresnelRoughness(f0, NoV, m.roughness);
        float3 environment = prefiltered.sample(linearClamp, R, level(m.roughness * frame.environment.z)).rgb;
        environment = mix(environment, m.reflection.rgb, float3(m.reflection.a));
        float specularOcclusion = SpecularOcclusion(NoV, m.occlusion, m.roughness);
        float3 incoming = irradiance.sample(linearClamp, N).rgb * mix(1.0, shadow, 0.35);
        float3 ambient = incoming * diffuseColor * (1.0 - Fr) * m.occlusion * frame.environment.x;
        ambient += environment * (f0 * split.x + split.y) * specularOcclusion * frame.environment.y;

        if (m.clearcoat > 0.0) {
            float coat = FresnelSchlick1(0.04, NoV) * m.clearcoat;
            float3 coatEnvironment = prefiltered.sample(linearClamp, R, level(m.clearcoatRoughness * frame.environment.z)).rgb;
            coatEnvironment = mix(coatEnvironment, m.reflection.rgb, float3(m.reflection.a));
            ambient = ambient * (1.0 - coat) + coatEnvironment * coat * specularOcclusion * frame.environment.y;
        }

        return direct + ambient + m.emissive;
    }

    float3 ApplyFog(float3 color, float3 position, constant FrameData& frame)
    {
        float viewDistance = length(position - frame.cameraPosition.xyz);
        float amount = 1.0 - exp(-max(viewDistance - frame.shadowParams.z, 0.0) * frame.fog.w);
        return mix(color, frame.fog.rgb, float3(saturate(amount)));
    }
    """#
}

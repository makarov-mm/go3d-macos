/// The Metal shaders, compiled when the game starts. Each part of the library lives in its own file; `ShaderSource.all`
/// joins them in order.
enum ShaderSource {
    static var all: String { [common, lighting, surface, stone, post, bake, interface].joined(separator: "\n") }

    /// The per-frame data, noise, display transforms and the GGX helpers that the other parts share.
    static let common = #"""
    #include <metal_stdlib>
    using namespace metal;

    constant float Pi = 3.14159265359;

    // Per frame; laid out as FrameData in RenderTypes.swift.
    struct FrameData {
        float4x4 viewProjection;
        float4x4 inverseViewProjection;
        float4x4 lightViewProjection;
        float4 cameraPosition; // xyz; w: time in seconds
        float4 lightDirection; // toward the light; w: world size of a shadow map texel
        float4 lightColor;     // radiance; w: tangent of the light's angular radius, for soft shadows
        float4 shadowParams;   // x: depth range of the shadow map, y: depth bias, z: where the fog begins
        float4 viewport;       // width, height, 1 / width, 1 / height
        float4 environment;    // x: diffuse light, y: reflected light, z: highest mip of the prefiltered map, w: background
        float4 accent;         // highlights
        float4 accentWarm;     // the last move, ko
        float4 fog;            // rgb; w: density
    };

    // Per pass: where the shading looks from, and the mirror for the reflections.
    struct PassData {
        float4 eye;    // xyz; w: 1 to leave out the shadows
        float4 mirror; // x: height of the mirror plane, y: 1 to mirror, z: half the size of the mirror
    };

    struct StoneVertex {
        float3 position;
        float3 normal;
    };

    struct SurfaceVertex {
        float3 position;
        float3 normal;
        float2 uv;
    };

    // A stone drawn, one of many in a buffer.
    struct StoneInstance {
        float4x4 model;
        float4 glow;   // rgb, strength
        float4 params; // x: dissolve, y: seed, z: height of the ground, w: the mark of the last move
        float4 extra;  // x: opacity
    };

    constexpr sampler linearClamp(coord::normalized, filter::linear, mip_filter::linear, address::clamp_to_edge);
    constexpr sampler nearestClamp(coord::normalized, filter::nearest, address::clamp_to_edge);
    constexpr sampler shadowCompare(coord::normalized, filter::linear, address::clamp_to_edge, compare_func::less_equal);
    constexpr sampler labelSampler(coord::normalized, filter::linear, mip_filter::linear, address::clamp_to_edge, max_anisotropy(8));

    float Luminance(float3 c) { return dot(c, float3(0.2126, 0.7152, 0.0722)); }

    // Display ------------------------------------------------------------------------------------------

    float3 RrtAndOdtFit(float3 v)
    {
        float3 a = v * (v + 0.0245786) - 0.000090537;
        float3 b = v * (0.983729 * v + 0.4329510) + 0.238081;
        return a / b;
    }

    // The ACES filmic curve, after Stephen Hill's fit.
    float3 Aces(float3 color)
    {
        const float3x3 inputMatrix = float3x3(float3(0.59719, 0.07600, 0.02840), float3(0.35458, 0.90834, 0.13383), float3(0.04823, 0.01566, 0.83777));
        const float3x3 outputMatrix = float3x3(float3(1.60475, -0.10208, -0.00327), float3(-0.53108, 1.10813, -0.07276), float3(-0.07367, -0.00605, 1.07602));
        return saturate(outputMatrix * RrtAndOdtFit(inputMatrix * color));
    }

    float3 EncodeSrgb(float3 c)
    {
        return mix(1.055 * pow(c, float3(1.0 / 2.4)) - 0.055, 12.92 * c, step(c, float3(0.0031308)));
    }

    // Noise ------------------------------------------------------------------------------------------

    float Hash12(float2 p)
    {
        float3 p3 = fract(p.xyx * 0.1031);
        p3 += dot(p3, p3.yzx + 33.33);
        return fract((p3.x + p3.y) * p3.z);
    }

    float Hash13(float3 p3)
    {
        p3 = fract(p3 * 0.1031);
        p3 += dot(p3, p3.zyx + 31.32);
        return fract((p3.x + p3.y) * p3.z);
    }

    float Noise(float2 p)
    {
        float2 i = floor(p);
        float2 f = fract(p);
        float2 u = f * f * (3.0 - 2.0 * f);
        return mix(mix(Hash12(i), Hash12(i + float2(1.0, 0.0)), u.x), mix(Hash12(i + float2(0.0, 1.0)), Hash12(i + float2(1.0, 1.0)), u.x), u.y);
    }

    float Noise(float3 p)
    {
        float3 i = floor(p);
        float3 f = fract(p);
        float3 u = f * f * (3.0 - 2.0 * f);
        float a = mix(mix(Hash13(i), Hash13(i + float3(1.0, 0.0, 0.0)), u.x), mix(Hash13(i + float3(0.0, 1.0, 0.0)), Hash13(i + float3(1.0, 1.0, 0.0)), u.x), u.y);
        float b = mix(mix(Hash13(i + float3(0.0, 0.0, 1.0)), Hash13(i + float3(1.0, 0.0, 1.0)), u.x), mix(Hash13(i + float3(0.0, 1.0, 1.0)), Hash13(i + float3(1.0, 1.0, 1.0)), u.x), u.y);
        return mix(a, b, u.z);
    }

    float Fbm(float2 p)
    {
        float sum = 0.0, amplitude = 0.5;
        for (int i = 0; i < 5; ++i) {
            sum += amplitude * Noise(p);
            p = float2x2(float2(1.6, 1.2), float2(-1.2, 1.6)) * p + 7.13;
            amplitude *= 0.5;
        }
        return sum;
    }

    float Fbm(float3 p)
    {
        float sum = 0.0, amplitude = 0.5;
        for (int i = 0; i < 4; ++i) {
            sum += amplitude * Noise(p);
            p = p * 2.03 + float3(5.1, 1.7, 9.2);
            amplitude *= 0.5;
        }
        return sum;
    }

    // Anti-aliasing and shapes -------------------------------------------------------------------------

    // The share of a pixel that a line covers: the pixel is `pixel` wide with its middle `d` from the line's middle,
    // and the line reaches `halfWidth` to either side. Thin lines fade instead of breaking up.
    float LineCoverage(float d, float halfWidth, float pixel)
    {
        return saturate((min(d + 0.5 * pixel, halfWidth) - max(d - 0.5 * pixel, -halfWidth)) / pixel);
    }

    // Per-pixel noise for dithering and for rotating sample patterns.
    float InterleavedGradientNoise(float2 pixel)
    {
        return fract(52.9829189 * fract(dot(pixel, float2(0.06711056, 0.00583715))));
    }

    float RoundedBox(float2 p, float2 halfSize, float radius)
    {
        float2 q = abs(p) - halfSize + radius;
        return length(max(q, float2(0.0))) + min(max(q.x, q.y), 0.0) - radius;
    }

    // GGX ------------------------------------------------------------------------------------------------

    float DistributionGgx(float NoH, float roughness)
    {
        float a = roughness * roughness;
        float a2 = a * a;
        float d = NoH * NoH * (a2 - 1.0) + 1.0;
        return a2 / (Pi * d * d);
    }

    // Directions of cube map texels, and sample patterns, for the light probes.
    float3 CubeDirection(uint3 texel, float size)
    {
        float2 st = (float2(texel.xy) + 0.5) / size * 2.0 - 1.0;
        switch (texel.z) {
        case 0: return normalize(float3(1.0, -st.y, -st.x));
        case 1: return normalize(float3(-1.0, -st.y, st.x));
        case 2: return normalize(float3(st.x, 1.0, st.y));
        case 3: return normalize(float3(st.x, -1.0, -st.y));
        case 4: return normalize(float3(st.x, -st.y, 1.0));
        default: return normalize(float3(-st.x, -st.y, -1.0));
        }
    }

    float2 Hammersley(uint i, uint count)
    {
        return float2(float(i) / float(count), float(reverse_bits(i)) * 2.3283064365386963e-10);
    }

    float3x3 TangentFrame(float3 n)
    {
        float3 up = abs(n.y) < 0.999 ? float3(0.0, 1.0, 0.0) : float3(1.0, 0.0, 0.0);
        float3 tangent = normalize(cross(up, n));
        return float3x3(tangent, cross(n, tangent), n);
    }

    float3 ImportanceSampleGgx(float2 xi, float roughness)
    {
        float a = roughness * roughness;
        float phi = 2.0 * Pi * xi.x;
        float cosTheta = sqrt((1.0 - xi.y) / (1.0 + (a * a - 1.0) * xi.y));
        float sinTheta = sqrt(1.0 - cosTheta * cosTheta);
        return float3(sinTheta * cos(phi), sinTheta * sin(phi), cosTheta);
    }

    // One triangle that covers the screen, at the far plane; uv from the top left, as Metal's textures read.
    struct FullscreenVaryings {
        float4 position [[position]];
        float2 uv;
        float2 ndc;
    };

    vertex FullscreenVaryings fullscreenVertex(uint vid [[vertex_id]])
    {
        float2 p = float2(float((vid << 1) & 2), float(vid & 2));
        FullscreenVaryings out;
        out.ndc = p * 2.0 - 1.0;
        out.position = float4(out.ndc, 1.0, 1.0);
        out.uv = float2(p.x, 1.0 - p.y);
        return out;
    }
    """#
}

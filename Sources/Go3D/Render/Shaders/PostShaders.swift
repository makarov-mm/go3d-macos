extension ShaderSource {
    /// Post-processing: the resolve of the multisampled scene, the bloom chain and the final image.
    static let post = #"""
    // Averages the samples of each pixel, weighting bright ones down so highlights keep smooth edges.
    fragment float4 resolveFragment(FullscreenVaryings in [[stage_in]], texture2d_ms<float> source [[texture(0)]])
    {
        uint2 pixel = uint2(in.position.xy);
        uint samples = source.get_num_samples();
        float3 sum = float3(0.0);
        float weights = 0.0;
        for (uint i = 0; i < samples; ++i) {
            float3 color = max(source.read(pixel, i).rgb, float3(0.0));
            float weight = 1.0 / (1.0 + Luminance(color));
            sum += color * weight;
            weights += weight;
        }
        return float4(sum / weights, 1.0);
    }

    float3 BloomTap(texture2d<float> source, float2 uv, float2 offset, float2 texel)
    {
        return max(source.sample(linearClamp, uv + offset * texel, level(0.0)).rgb, float3(0.0));
    }

    // Halves the image with a 13-tap filter; the first step weights bright samples down against flicker.
    // params: xy the size of a texel of the source, z 1 for the first step.
    fragment float4 bloomDownFragment(FullscreenVaryings in [[stage_in]],
                                      constant float4& params [[buffer(0)]],
                                      texture2d<float> source [[texture(0)]])
    {
        float2 uv = in.uv, t = params.xy;
        float3 a = BloomTap(source, uv, float2(-2.0, 2.0), t), b = BloomTap(source, uv, float2(0.0, 2.0), t), c = BloomTap(source, uv, float2(2.0, 2.0), t);
        float3 d = BloomTap(source, uv, float2(-2.0, 0.0), t), e = BloomTap(source, uv, float2(0.0, 0.0), t), f = BloomTap(source, uv, float2(2.0, 0.0), t);
        float3 g = BloomTap(source, uv, float2(-2.0, -2.0), t), h = BloomTap(source, uv, float2(0.0, -2.0), t), i = BloomTap(source, uv, float2(2.0, -2.0), t);
        float3 j = BloomTap(source, uv, float2(-1.0, 1.0), t), k = BloomTap(source, uv, float2(1.0, 1.0), t);
        float3 l = BloomTap(source, uv, float2(-1.0, -1.0), t), m = BloomTap(source, uv, float2(1.0, -1.0), t);

        float3 result;
        if (params.z > 0.5) {
            // Each group of four counts less the brighter it is, so lone bright pixels do not flicker.
            float3 groups[5] = { (j + k + l + m) * 0.25, (a + b + d + e) * 0.25, (b + c + e + f) * 0.25, (d + e + g + h) * 0.25, (e + f + h + i) * 0.25 };
            float share[5] = { 0.5, 0.125, 0.125, 0.125, 0.125 };
            float3 sum = float3(0.0);
            float weights = 0.0;
            for (int n = 0; n < 5; ++n) {
                float weight = share[n] / (1.0 + Luminance(groups[n]));
                sum += groups[n] * weight;
                weights += weight;
            }
            result = sum / weights;
        }
        else {
            result = e * 0.125 + (a + c + g + i) * 0.03125 + (b + d + f + h) * 0.0625 + (j + k + l + m) * 0.125;
        }
        return float4(result, 1.0);
    }

    // Doubles the image with a tent filter; added onto the next larger level. params: xy the size of a source texel.
    fragment float4 bloomUpFragment(FullscreenVaryings in [[stage_in]],
                                    constant float4& params [[buffer(0)]],
                                    texture2d<float> source [[texture(0)]])
    {
        float2 uv = in.uv, t = params.xy;
        float3 sum = source.sample(linearClamp, uv, level(0.0)).rgb * 4.0;
        sum += (source.sample(linearClamp, uv + float2(-t.x, 0.0), level(0.0)).rgb + source.sample(linearClamp, uv + float2(t.x, 0.0), level(0.0)).rgb +
                source.sample(linearClamp, uv + float2(0.0, -t.y), level(0.0)).rgb + source.sample(linearClamp, uv + float2(0.0, t.y), level(0.0)).rgb) * 2.0;
        sum += source.sample(linearClamp, uv + float2(-t.x, -t.y), level(0.0)).rgb + source.sample(linearClamp, uv + float2(t.x, -t.y), level(0.0)).rgb +
               source.sample(linearClamp, uv + float2(-t.x, t.y), level(0.0)).rgb + source.sample(linearClamp, uv + float2(t.x, t.y), level(0.0)).rgb;
        return float4(sum / 16.0, 1.0);
    }

    // Laid out as CompositeParams in RenderTypes.swift.
    struct CompositeParams {
        float4 settings;       // x: exposure, y: bloom strength, z: vignette, w: number of panels
        float4 viewport;       // width, height, 1 / width, 1 / height
        float4 panels[4];      // center x, center y, half width, half height, in pixels from the top left
        float4 panelStyles[4]; // x: corner radius, y: opacity
    };

    // The final image: bloom, frosted glass behind the panels, exposure, filmic tone mapping, vignette, dither.
    fragment float4 compositeFragment(FullscreenVaryings in [[stage_in]],
                                      constant CompositeParams& params [[buffer(0)]],
                                      texture2d<float> scene [[texture(0)]],
                                      texture2d<float> bloom [[texture(1)]],
                                      texture2d<float> blur [[texture(2)]])
    {
        float3 color = scene.sample(linearClamp, in.uv, level(0.0)).rgb;
        float3 glow = bloom.sample(linearClamp, in.uv, level(0.0)).rgb / 6.0;
        color = mix(color, glow, float3(params.settings.y));

        float2 pixel = in.position.xy;
        int count = int(params.settings.w + 0.5);
        for (int i = 0; i < count; ++i) {
            float d = RoundedBox(pixel - params.panels[i].xy, params.panels[i].zw, params.panelStyles[i].x);
            float inside = 1.0 - smoothstep(-1.0, 1.0, d);
            float3 frosted = blur.sample(linearClamp, in.uv, level(0.0)).rgb / 4.0;
            color = mix(color, frosted * 0.45, float3(inside * params.panelStyles[i].y));
        }

        color = Aces(color * params.settings.x);

        float2 centered = in.uv - 0.5;
        centered.x *= params.viewport.x * params.viewport.w;
        color *= 1.0 - params.settings.z * smoothstep(0.25, 1.05, length(centered));

        color = EncodeSrgb(color);
        color += (InterleavedGradientNoise(in.position.xy) - 0.5) / 255.0;
        return float4(color, 1.0);
    }
    """#
}

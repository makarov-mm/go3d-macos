extension ShaderSource {
    /// The interface, in pixels from the top left corner: text from the font atlases, and shapes drawn from their
    /// distance functions.
    static let interface = #"""
    // Laid out as InterfaceVertex in UiPainter.swift.
    struct InterfaceVertex {
        float4 positionUv; // xy: pixels from the top left, zw: uv
        float4 color;      // straight alpha
        float4 shape;      // x: kind; yzw depend on it
    };

    struct InterfaceVaryings {
        float4 position [[position]];
        float2 uv;
        float4 color;
        float4 shape [[flat]];
    };

    constexpr sampler textSampler(coord::normalized, filter::linear, address::clamp_to_edge);

    vertex InterfaceVaryings interfaceVertex(uint vid [[vertex_id]],
                                             const device InterfaceVertex* vertices [[buffer(0)]],
                                             constant float4& screen [[buffer(1)]]) // width, height
    {
        InterfaceVertex v = vertices[vid];
        InterfaceVaryings out;
        out.position = float4(v.positionUv.x / screen.x * 2.0 - 1.0, 1.0 - v.positionUv.y / screen.y * 2.0, 0.0, 1.0);
        out.uv = v.positionUv.zw;
        out.color = v.color;
        out.shape = v.shape;
        return out;
    }

    float Triangle(float2 p, float2 p0, float2 p1, float2 p2)
    {
        float2 e0 = p1 - p0, e1 = p2 - p1, e2 = p0 - p2;
        float2 v0 = p - p0, v1 = p - p1, v2 = p - p2;
        float2 q0 = v0 - e0 * clamp(dot(v0, e0) / dot(e0, e0), 0.0, 1.0);
        float2 q1 = v1 - e1 * clamp(dot(v1, e1) / dot(e1, e1), 0.0, 1.0);
        float2 q2 = v2 - e2 * clamp(dot(v2, e2) / dot(e2, e2), 0.0, 1.0);
        float s = sign(e0.x * e2.y - e0.y * e2.x);
        float2 d = min(min(float2(dot(q0, q0), s * (v0.x * e0.y - v0.y * e0.x)), float2(dot(q1, q1), s * (v1.x * e1.y - v1.y * e1.x))),
                       float2(dot(q2, q2), s * (v2.x * e2.y - v2.y * e2.x)));
        return -sqrt(d.x) * sign(d.y);
    }

    // x - y * floor(x / y), as GLSL's mod.
    float Mod(float x, float y) { return x - y * floor(x / y); }

    fragment float4 interfaceFragment(InterfaceVaryings in [[stage_in]],
                                      texture2d<float> font0 [[texture(0)]],
                                      texture2d<float> font1 [[texture(1)]],
                                      texture2d<float> font2 [[texture(2)]])
    {
        int kind = int(in.shape.x + 0.5);
        float alpha = 1.0;
        if (kind == 0) {
            alpha = font0.sample(textSampler, in.uv, level(0.0)).r;
        }
        else if (kind == 1) {
            alpha = font1.sample(textSampler, in.uv, level(0.0)).r;
        }
        else if (kind == 2) {
            alpha = font2.sample(textSampler, in.uv, level(0.0)).r;
        }
        else if (kind == 3) {
            // A rounded rectangle; uv is the position from its center, yz its half size, w the corner radius.
            alpha = saturate(0.5 - RoundedBox(in.uv, in.shape.yz, in.shape.w));
        }
        else if (kind == 4) {
            // A soft shadow, blurred by w.
            float d = RoundedBox(in.uv, in.shape.yz, in.shape.w);
            alpha = 1.0 - smoothstep(-in.shape.w, in.shape.w, d);
            alpha *= alpha;
        }
        else if (kind == 5) {
            // The outline of a rounded rectangle.
            float d = RoundedBox(in.uv, in.shape.yz, in.shape.w);
            alpha = saturate(1.0 - abs(d + 0.75));
        }
        else if (kind == 6) {
            // A spinning arc: y is the radius, z the thickness, w the angle of its head.
            float r = length(in.uv);
            float ring = saturate(in.shape.z * 0.5 + 0.5 - abs(r - in.shape.y));
            float angle = Mod(atan2(in.uv.y, in.uv.x) - in.shape.w, 6.2831853);
            alpha = ring * smoothstep(1.0, 5.5, angle) * (1.0 - smoothstep(5.6, 6.2, angle));
        }
        else if (kind == 7) {
            // A disc of radius y.
            alpha = saturate(in.shape.y + 0.5 - length(in.uv));
        }
        else if (kind == 8) {
            // A triangle pointing along x, mirrored when w is negative; y and z are its half width and height.
            float2 p = float2(in.uv.x * sign(in.shape.w), in.uv.y);
            alpha = saturate(0.5 - Triangle(p, float2(-in.shape.y, -in.shape.z), float2(in.shape.y, 0.0), float2(-in.shape.y, in.shape.z)));
        }
        return float4(in.color.rgb, in.color.a * alpha);
    }
    """#
}

extension ShaderSource {
    /// The stones, drawn many at once, each instance with its own matrix and look; in the reflection pass, mirrored in
    /// the board. Slate or shell, glass, yunzi or acrylic, with a ring on the stone played last, a glow, a dissolve, and
    /// seen through when dead or where a click would play.
    static let stone = #"""
    // The look of the stones of one color; laid out as StoneMaterial in RenderTypes.swift.
    struct StoneMaterial {
        float4 albedo;  // rgb
        float4 surface; // roughness, metallic, clearcoat, clearcoat roughness
        float4 style;   // x: subsurface, y: pattern strength, z: pattern (0 none, 1 shell, 2 slate, 3 glass, 4 yunzi), w: 1 for black
        float4 trim;    // rgb, strength: a glowing ring round the edge
        float4 edge;    // rgb, strength: light coming through the thin edge
    };

    struct StoneVaryings {
        float4 position [[position]];
        float3 world;
        float3 normal;
        float3 local;
        float4 glow [[flat]];
        float4 params [[flat]];
        float opacity [[flat]];
        float clip; // below zero, outside the mirror
    };

    constant float StoneRadius = 0.475;

    vertex StoneVaryings stoneVertex(uint vid [[vertex_id]],
                                     uint iid [[instance_id]],
                                     const device StoneVertex* vertices [[buffer(0)]],
                                     const device StoneInstance* stones [[buffer(1)]],
                                     constant FrameData& frame [[buffer(2)]],
                                     constant PassData& pass [[buffer(3)]])
    {
        StoneVertex v = vertices[vid];
        StoneInstance stone = stones[iid];
        float4 world = stone.model * float4(v.position, 1.0);
        StoneVaryings out;
        out.world = world.xyz;
        out.normal = (stone.model * float4(v.normal, 0.0)).xyz;
        out.local = v.position;
        out.glow = stone.glow;
        out.params = stone.params;
        out.opacity = stone.extra.x;
        out.clip = 1.0;
        if (pass.mirror.y > 0.5) {
            // Only the stones over the board are mirrored in it.
            float2 center = stone.model[3].xz;
            out.clip = min(world.y - pass.mirror.x, pass.mirror.z - max(abs(center.x), abs(center.y)));
            world.y = 2.0 * pass.mirror.x - world.y;
        }
        out.position = frame.viewProjection * world;
        return out;
    }

    fragment float4 stoneFragment(StoneVaryings in [[stage_in]],
                                  bool frontFacing [[front_facing]],
                                  constant FrameData& frame [[buffer(0)]],
                                  constant PassData& pass [[buffer(1)]],
                                  constant StoneMaterial& material [[buffer(2)]],
                                  depth2d<float> shadowMap [[texture(0)]],
                                  texturecube<float> irradiance [[texture(1)]],
                                  texturecube<float> prefiltered [[texture(2)]],
                                  texture2d<float> brdf [[texture(3)]])
    {
        // Measured before anything is discarded, while the neighbouring pixels still run.
        float3 N = normalize(in.normal);
        float spread = NormalSpread(N);
        float3 localPixel = fwidth(in.local);
        float radiusPixel = max(fwidth(length(in.local.xz)), 1e-5);

        if (in.clip < 0.0)
            discard_fragment();
        float seed = in.params.y;
        float3 emissive = float3(0.0);
        if (in.params.x > 0.0) {
            float n = Fbm(in.local * 9.0 + 3.0 + seed * 5.0);
            float threshold = in.params.x * 1.2 - 0.1;
            if (n < threshold)
                discard_fragment();
            emissive += frame.accent.rgb * (1.0 - smoothstep(0.0, 0.06, n - threshold)) * 8.0;
        }

        if (!frontFacing)
            N = -N;
        float3 V = normalize(pass.eye.xyz - in.world);

        Material m = DefaultMaterial(material.albedo.rgb, material.surface.x);
        m.metallic = material.surface.y;
        m.clearcoat = material.surface.z;
        m.clearcoatRoughness = material.surface.w;
        m.subsurface = material.style.x;

        float radius = length(in.local.xz);
        float edge = radius / StoneRadius; // 0 in the middle, 1 at the edge
        int pattern = int(material.style.z + 0.5);
        float footprint = length(localPixel);
        if (pattern == 1) {
            // Clamshell: fine growth lines across the face, gently bowed, fading where finer than a pixel.
            float3 q = in.local + float3(seed * 0.3, 0.0, seed * 0.7);
            float bands = q.z * 70.0 + 9.0 * q.x * q.x + 1.5 * Noise(q.xz * 6.0 + seed * 9.0);
            float band = 0.5 + 0.5 * sin(bands);
            float fine = mix(band, 0.5, smoothstep(0.006, 0.02, footprint));
            float broad = Noise(float2(q.z * 9.0, seed * 13.0));
            m.albedo *= 1.0 - material.style.y * (0.06 * fine + 0.05 * broad);
        }
        else if (pattern == 2) {
            // Slate: matte, with a faint mottle and fine grain.
            float mottle = Fbm(in.local * 9.0 + seed * 11.0);
            float grain = mix(Noise(in.local.xz * 260.0 + seed), 0.5, smoothstep(0.002, 0.006, footprint));
            m.albedo *= 0.85 + 0.3 * material.style.y * mottle + 0.1 * material.style.y * (grain - 0.5);
            m.roughness = clamp(m.roughness + 0.1 * (mottle - 0.5), 0.05, 1.0);
        }
        else if (pattern == 3) {
            // Glass: a swirl deep inside.
            float swirl = Fbm(in.local * 5.0 + seed * 7.0);
            m.albedo *= 0.85 + 0.3 * material.style.y * swirl;
        }
        else if (pattern == 4) {
            // Yunzi: soft and even, with a faint cloud.
            m.albedo *= 0.93 + 0.14 * material.style.y * Fbm(in.local * 4.0 + seed * 3.0);
        }

        // The stone played last carries a ring on its upper face, in the color of the other side.
        if (in.params.w > 0.0 && in.local.y > 0.0) {
            float mark = LineCoverage(abs(radius - 0.19), 0.03, radiusPixel) * in.params.w;
            float3 ring = material.style.w > 0.5 ? float3(0.85, 0.84, 0.8) : float3(0.03, 0.03, 0.035);
            m.albedo = mix(m.albedo, ring, float3(mark));
            m.roughness = mix(m.roughness, 0.4, mark);
            m.metallic *= 1.0 - mark;
        }

        // The ground darkens what faces it, near the bottom most.
        float above = in.world.y - in.params.z;
        float ground = mix(0.35, 1.0, smoothstep(0.0, 0.3, above));
        m.occlusion = mix(1.0, ground, saturate(0.6 - N.y * 0.6));

        // Light through the thin edge, for yunzi and glass; a neon ring for the acrylic set.
        float rim = smoothstep(0.75, 1.0, edge);
        m.emissive = emissive + material.edge.rgb * material.edge.a * rim * saturate(dot(-V, normalize(frame.lightDirection.xyz)) * 0.5 + 0.5);
        m.emissive += material.trim.rgb * material.trim.a * LineCoverage(abs(in.local.y), 0.012, max(localPixel.y, 1e-5)) * step(0.9, edge);

        m.roughness = WidenRoughness(m.roughness, spread);
        m.clearcoatRoughness = WidenRoughness(m.clearcoatRoughness, spread);
        float shadow = pass.eye.w > 0.5 ? 1.0 : Shadow(in.world, N, in.position.xy, frame, shadowMap);
        float3 color = Shade(m, in.world, N, V, shadow, frame, irradiance, prefiltered, brdf);

        // The glow of stones about to be taken: a halo at the silhouette and some light all over.
        float NoV = saturate(dot(N, V));
        color += in.glow.rgb * in.glow.a * (0.22 + 1.6 * pow(1.0 - NoV, 3.0));

        return float4(ApplyFog(color, in.world, frame), in.opacity);
    }

    // The depth of the stones as the key light sees them; a dissolving stone casts its remaining part.
    struct StoneDepthVaryings {
        float4 position [[position]];
        float3 local;
        float2 dissolve [[flat]]; // amount, seed
    };

    vertex StoneDepthVaryings shadowStoneVertex(uint vid [[vertex_id]],
                                                uint iid [[instance_id]],
                                                const device StoneVertex* vertices [[buffer(0)]],
                                                const device StoneInstance* stones [[buffer(1)]],
                                                constant FrameData& frame [[buffer(2)]])
    {
        StoneDepthVaryings out;
        out.local = vertices[vid].position;
        out.dissolve = stones[iid].params.xy;
        out.position = frame.lightViewProjection * stones[iid].model * float4(out.local, 1.0);
        return out;
    }

    fragment void shadowStoneFragment(StoneDepthVaryings in [[stage_in]])
    {
        if (in.dissolve.x > 0.0 && Fbm(in.local * 9.0 + 3.0 + in.dissolve.y * 5.0) < in.dissolve.x * 1.2 - 0.1)
            discard_fragment();
    }
    """#
}

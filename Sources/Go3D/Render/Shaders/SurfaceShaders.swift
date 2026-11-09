extension ShaderSource {
    /// The board with its lines, hoshi, coordinates and marks, its sides, the table, and the turned bowls and lids; and
    /// their depth for the shadow map.
    static let surface = #"""
    // The material of the surfaces for the theme and the frame; laid out as SurfaceMaterial in RenderTypes.swift.
    struct SurfaceMaterial {
        float4 boardColor;      // rgb
        float4 boardSurface;    // roughness, clearcoat, clearcoat roughness, pattern (0 kaya, 1 bamboo, 2 slate, 3 glass)
        float4 boardReflection; // x: reflection strength, y: reflection blur
        float4 gridColor;       // rgb
        float4 grid;            // x: half the width of a line, y: metallic, z: roughness, w: glow
        float4 boardShape;      // x: lines, y: from the middle to the outer lines, z: to the edge, w: radius of the hoshi
        float4 bowlColor;       // rgb
        float4 bowlSurface;     // roughness, clearcoat, pattern (0 wood, 1 lacquer), wood seed
        float4 tableColor;      // rgb
        float4 tableSurface;    // roughness, pattern (0 felt, 1 wood, 2 neon grid, 3 stone), sheen, grid glow
        float4 tableFade;       // xy: the table darkens between these distances from the middle
        float4 markStyle;       // x: the territory shown faintly, as an estimate; y: 1 to show the coordinates
        float4 discs[4];        // the feet of the bowls and lids: xz, radius, darkness
    };

    // One surface drawn: where it stands, and what it is.
    struct SurfaceDraw {
        float4x4 model;
        float4 bowlShape; // of the bowl drawn: the middle (xz), the height of its rim, its radius; 0 for a lid
        float4 kind;      // x: 0 the top of the board, 1 its sides, 2 the table, 3 bowls and lids
    };

    struct SurfaceVaryings {
        float4 position [[position]];
        float3 world;
        float3 normal;
        float2 uv;
    };

    // What is marked on each point of the board, as bits; see SceneMark in RenderTypes.swift.
    constant uint BlackArea = 1;
    constant uint WhiteArea = 2;
    constant uint HoverMark = 4;
    constant uint HintMark = 8;
    constant uint KoMark = 16;
    constant uint StoneHere = 32;

    vertex SurfaceVaryings surfaceVertex(uint vid [[vertex_id]],
                                         const device SurfaceVertex* vertices [[buffer(0)]],
                                         constant SurfaceDraw& draw [[buffer(1)]],
                                         constant FrameData& frame [[buffer(2)]])
    {
        SurfaceVertex v = vertices[vid];
        float4 world = draw.model * float4(v.position, 1.0);
        SurfaceVaryings out;
        out.world = world.xyz;
        out.normal = (draw.model * float4(v.normal, 0.0)).xyz;
        out.uv = v.uv;
        out.position = frame.viewProjection * world;
        return out;
    }

    // Wood with its grain along x: growth lines of uneven spacing and strength, fine fibres and a soft figure. Detail
    // finer than the footprint, the size of a pixel in p, fades to its average instead of flickering.
    float3 Wood(float2 p, float3 color, float seed, float footprint)
    {
        p += float2(seed * 31.7, seed * 17.3);
        // The growth lines: their spacing drifts across the grain, and they wander a little along it.
        float t = p.y * 7.0 + 2.5 * Fbm(float2(p.y * 0.8, seed * 5.0)) + 0.8 * Fbm(float2(p.x * 0.3, p.y * 1.2)) + 0.2 * sin(p.x * 1.1 + seed * 6.0);
        float ring = floor(t);
        float phase = t - ring;
        float width = 0.2 + 0.3 * Hash12(float2(ring, seed));
        float late = smoothstep(0.0, 0.08, phase) * (1.0 - smoothstep(width, width + 0.25, phase));
        late *= 0.35 + 0.9 * Hash12(float2(ring, seed + 7.0));
        late = mix(late, 0.3, smoothstep(0.04, 0.12, footprint));
        float fibers = 0.5 * Noise(float2(p.x * 3.0, p.y * 260.0)) + 0.5 * Noise(float2(p.x * 7.0, p.y * 600.0));
        fibers = mix(fibers, 0.5, smoothstep(0.001, 0.004, footprint));
        float figure = Noise(p * float2(0.8, 2.2) + seed * 9.0);
        return color * (1.0 - 0.2 * late) * (0.9 + 0.16 * fibers) * (0.9 + 0.2 * figure);
    }

    float3 Marble(float2 p, float3 color, float3 veinColor, float seed)
    {
        p += seed * 10.0;
        float warp = Fbm(p * 1.3) * 4.5;
        float wave = abs(sin((p.x * 1.4 + p.y * 0.9 + warp) * 2.6));
        float vein = pow(1.0 - wave, 14.0) + 0.35 * pow(1.0 - abs(sin((p.x * 3.1 - p.y * 2.2 + warp * 1.7) * 3.0)), 30.0);
        float3 c = color * (0.9 + 0.2 * Fbm(p * 2.7 + 5.0));
        return mix(c, veinColor, float3(saturate(vein) * 0.75));
    }

    // Felt: fine fibres and a soft mottling, fading to their average where they are finer than a pixel.
    float3 Felt(float2 p, float3 color, float footprint)
    {
        float fine = mix(Noise(p * 260.0), 0.5, smoothstep(0.002, 0.006, footprint));
        float coarse = mix(Noise(p * 90.0 + 3.0), 0.5, smoothstep(0.006, 0.018, footprint));
        return color * (0.84 + 0.3 * (0.6 * fine + 0.4 * coarse)) * (0.92 + 0.16 * Fbm(p * 0.9));
    }

    // The top of the board: kaya with its fine straight grain, laminated bamboo, slate or dark glass.
    float3 BoardAlbedo(float2 p, float footprint, int pattern, float3 boardColor)
    {
        if (pattern == 0)
            return Wood(float2(p.y, p.x) * float2(0.25, 0.9), boardColor, 0.53, footprint);
        if (pattern == 1) {
            // Strips of bamboo along the board, each its own shade, with fine fibres and darker joints.
            float strip = floor(p.x / 0.36);
            float across = fract(p.x / 0.36);
            float3 c = boardColor * (0.9 + 0.2 * Hash12(float2(strip, 1.7)));
            float fibers = mix(Noise(float2(p.x * 90.0, p.y * 4.0)), 0.5, smoothstep(0.004, 0.012, footprint));
            float joint = 1.0 - smoothstep(0.0, 0.05, min(across, 1.0 - across));
            float knot = smoothstep(0.85, 1.0, sin(p.y * 0.9 + strip * 2.3) * 0.5 + 0.5);
            return c * (0.92 + 0.16 * fibers) * (1.0 - 0.18 * mix(joint, 0.3, smoothstep(0.02, 0.06, footprint))) * (1.0 - 0.12 * knot);
        }
        if (pattern == 2)
            return Marble(p * 0.21, boardColor, boardColor * 3.0 + 0.04, 3.0);
        return boardColor * (0.9 + 0.2 * Noise(p * 6.0));
    }

    bool IsStar(int2 point, int lines)
    {
        int edge = lines >= 13 ? 3 : 2, far = lines - 1 - edge, middle = lines / 2;
        bool x = point.x == edge || point.x == far, y = point.y == edge || point.y == far;
        if (lines >= 19) {
            x = x || point.x == middle;
            y = y || point.y == middle;
        }
        bool center = (lines & 1) == 1 && point.x == middle && point.y == middle;
        return (x && y) || center;
    }

    float ContactShadow(float2 xz, constant SurfaceMaterial& material)
    {
        float shade = 1.0;
        for (int i = 0; i < 4; ++i) {
            float4 disc = material.discs[i];
            float d = length(xz - disc.xy);
            shade *= 1.0 - disc.w * (1.0 - smoothstep(disc.z * 0.55, disc.z * 1.9, d));
        }
        return shade;
    }

    fragment float4 surfaceFragment(SurfaceVaryings in [[stage_in]],
                                    constant FrameData& frame [[buffer(0)]],
                                    constant PassData& pass [[buffer(1)]],
                                    constant SurfaceMaterial& material [[buffer(2)]],
                                    constant SurfaceDraw& draw [[buffer(3)]],
                                    constant uchar* marks [[buffer(4)]],
                                    depth2d<float> shadowMap [[texture(0)]],
                                    texturecube<float> irradiance [[texture(1)]],
                                    texturecube<float> prefiltered [[texture(2)]],
                                    texture2d<float> brdf [[texture(3)]],
                                    texture2d<float> reflection [[texture(4)]],
                                    texture2d<float> labels [[texture(5)]])
    {
        float3 N = normalize(in.normal);
        float3 V = normalize(pass.eye.xyz - in.world);
        float time = frame.cameraPosition.w;
        Material m = DefaultMaterial(float3(0.5), 0.5);
        float3 glow = float3(0.0);
        float4 planar = float4(0.0);
        int kind = int(draw.kind.x + 0.5);

        if (kind == 0) {
            int lines = int(material.boardShape.x + 0.5);
            float2 grid = in.world.xz + material.boardShape.y;      // the lines at whole numbers, 0 to lines - 1
            float2 pixel = max(fwidth(grid), float2(1e-5));         // the size of a pixel on the board
            float footprint = length(pixel);
            float soft = max(0.01, 0.75 * footprint);               // sharp edges softened to a pixel when the board is far
            float pulse = 0.5 + 0.5 * sin(time * 3.5);
            int pattern = int(material.boardSurface.w + 0.5);
            m.albedo = BoardAlbedo(in.world.xz, footprint, pattern, material.boardColor.rgb);
            m.roughness = material.boardSurface.x;
            m.clearcoat = material.boardSurface.y;
            m.clearcoatRoughness = material.boardSurface.z;

            // The nearest point and the marks round it: the stones darken the board under and beside them.
            float last = float(lines - 1);
            int2 nearest = int2(clamp(round(grid), float2(0.0), float2(last)));
            float shade = 1.0;
            for (int dy = -1; dy <= 1; ++dy) {
                for (int dx = -1; dx <= 1; ++dx) {
                    int2 point = nearest + int2(dx, dy);
                    if (point.x < 0 || point.y < 0 || point.x >= lines || point.y >= lines)
                        continue;
                    if ((uint(marks[point.x + 19 * point.y]) & StoneHere) != 0u)
                        shade *= 1.0 - 0.5 * (1.0 - smoothstep(0.3, 0.72, length(grid - float2(point))));
                }
            }
            uint pointMarks = uint(marks[nearest.x + 19 * nearest.y]);
            float2 local = grid - float2(nearest);
            float d = length(local);
            float2 box = abs(local);

            // The lines, the outer ones thicker, and the hoshi, averaged over the pixel.
            float2 offset = grid - round(grid);
            float2 lineIndex = round(grid);
            float2 outer = select(float2(0.0), float2(1.0), lineIndex == float2(0.0)) + select(float2(0.0), float2(1.0), lineIndex == float2(last));
            float2 width = float2(material.grid.x) * mix(float2(1.0), float2(1.7), outer);
            // Each line runs between the outer lines and no further.
            float reach = material.grid.x * 1.7;
            bool withinRows = grid.y > -reach && grid.y < last + reach, withinColumns = grid.x > -reach && grid.x < last + reach;
            float ink = 0.0;
            if (withinRows && lineIndex.x >= 0.0 && lineIndex.x <= last)
                ink = max(ink, LineCoverage(abs(offset.x), width.x, pixel.x));
            if (withinColumns && lineIndex.y >= 0.0 && lineIndex.y <= last)
                ink = max(ink, LineCoverage(abs(offset.y), width.y, pixel.y));
            if (IsStar(nearest, lines))
                ink = max(ink, 1.0 - smoothstep(material.boardShape.w - 0.6 * footprint, material.boardShape.w + 0.6 * footprint, d));
            // The coordinates, written round the lines.
            float label = material.markStyle.y > 0.5 ? labels.sample(labelSampler, (in.world.xz + material.boardShape.z) / (2.0 * material.boardShape.z)).r * 0.85 : 0.0;
            ink = max(ink, label);
            m.albedo = mix(m.albedo, material.gridColor.rgb, float3(ink));
            m.metallic = mix(m.metallic, material.grid.y, ink);
            m.roughness = mix(m.roughness, material.grid.z, ink);
            glow += material.gridColor.rgb * material.grid.w * ink;

            // Territory, as small squares; the point under the pointer, a hint, and a ko that may not be taken back yet.
            float square = material.markStyle.x > 0.5 ? 0.13 : 0.17;
            float inSquare = (1.0 - smoothstep(square - soft, square + soft, box.x)) * (1.0 - smoothstep(square - soft, square + soft, box.y));
            float strength = material.markStyle.x > 0.5 ? 0.75 : 1.0;
            // A thin rim keeps a square of the board's own darkness or lightness in sight: light round black squares on
            // a dark board, dark round white squares on a light one.
            float rimEdge = square + 0.03;
            float outerSquare = (1.0 - smoothstep(rimEdge - soft, rimEdge + soft, box.x)) * (1.0 - smoothstep(rimEdge - soft, rimEdge + soft, box.y));
            float rim = max(outerSquare - inSquare, 0.0);
            float darkBoard = 1.0 - smoothstep(0.04, 0.15, Luminance(material.boardColor.rgb));
            if ((pointMarks & BlackArea) != 0u)
                m.albedo = mix(mix(m.albedo, float3(0.45), float3(rim * darkBoard * strength)), float3(0.015), float3(inSquare * strength));
            if ((pointMarks & WhiteArea) != 0u)
                m.albedo = mix(mix(m.albedo, float3(0.02), float3(rim * (1.0 - darkBoard) * 0.7 * strength)), float3(0.86, 0.85, 0.82), float3(inSquare * strength));
            if ((pointMarks & HoverMark) != 0u)
                glow += frame.accent.rgb * (1.0 - smoothstep(0.016 - soft, 0.016 + soft, abs(d - 0.52))) * 1.2;
            if ((pointMarks & HintMark) != 0u)
                glow += frame.accent.rgb * (1.0 - smoothstep(0.024 - soft, 0.024 + soft, abs(d - 0.5 - 0.04 * pulse))) * (1.6 + 0.8 * pulse);
            if ((pointMarks & KoMark) != 0u) {
                float outline = abs(max(box.x, box.y) - 0.2);
                glow += frame.accentWarm.rgb * (1.0 - smoothstep(0.015 - soft, 0.015 + soft, outline)) * 1.4;
            }

            // The stones mirrored in the polish, added over the shading below.
            float2 screen = in.position.xy * frame.viewport.zw + N.xz * 0.012;
            planar = reflection.sample(linearClamp, screen, level(material.boardReflection.y));
            m.occlusion = shade;
        }
        else if (kind == 1) {
            // The sides of the board: the same wood, its grain running round.
            int pattern = int(material.boardSurface.w + 0.5);
            bool alongX = abs(in.world.z) > abs(in.world.x);
            float2 along = alongX ? float2(in.world.x, in.world.y * 3.0 + in.world.z) : float2(in.world.z, in.world.y * 3.0 + in.world.x);
            float footprint = length(fwidth(along));
            m.albedo = pattern == 0 || pattern == 1 ? Wood(along * float2(0.4, 1.0), material.boardColor.rgb * 0.92, 0.29, footprint)
                                                    : BoardAlbedo(along, footprint, pattern, material.boardColor.rgb);
            m.roughness = material.boardSurface.x;
            m.clearcoat = material.boardSurface.y;
            m.clearcoatRoughness = material.boardSurface.z + 0.02;
            m.occlusion = mix(0.6, 1.0, smoothstep(-material.boardShape.z * 0.1 - 0.8, -0.1, in.world.y));
        }
        else if (kind == 3) {
            // Turned wood: the rings follow the turning, the grain runs round.
            float2 turned = float2(in.uv.y * 40.0, in.uv.x * 3.0);
            float footprint = length(fwidth(turned));
            m.albedo = Wood(turned, material.bowlColor.rgb, material.bowlSurface.w, footprint * 0.5);
            if (material.bowlSurface.z > 0.5)
                m.albedo = material.bowlColor.rgb * (0.92 + 0.08 * Noise(turned * 0.4));
            m.roughness = material.bowlSurface.x;
            m.clearcoat = material.bowlSurface.y;
            m.clearcoatRoughness = 0.08;
            m.occlusion = mix(0.55, 1.0, saturate(N.y * 0.5 + 0.6));
            // Inside a bowl, darker the deeper.
            if (draw.bowlShape.w > 0.0 && length(in.world.xz - draw.bowlShape.xy) < 0.79 * draw.bowlShape.w && in.world.y > draw.bowlShape.z - 0.3 * draw.bowlShape.w)
                m.occlusion = mix(1.0, 0.35, smoothstep(0.0, 0.22 * draw.bowlShape.w, draw.bowlShape.z - in.world.y));
        }
        else {
            int pattern = int(material.tableSurface.y + 0.5);
            float2 p = in.world.xz;
            float centerDistance = length(p);
            float footprint = length(fwidth(p));
            if (pattern == 0) {
                m.albedo = Felt(p, material.tableColor.rgb, footprint);
            }
            else if (pattern == 1) {
                m.albedo = Wood(p * float2(0.25, 0.9), material.tableColor.rgb, 0.81, footprint * 0.9);
            }
            else if (pattern == 2) {
                // The glowing grid of the first version of the game.
                m.albedo = material.tableColor.rgb;
                float2 minorCell = abs(fract(p - 0.5) - 0.5) / fwidth(p);
                float minorLine = 1.0 - saturate(min(minorCell.x, minorCell.y) - 0.5);
                float2 majorCell = abs(fract(p * 0.2 - 0.5) - 0.5) / fwidth(p * 0.2);
                float majorLine = 1.0 - saturate(min(majorCell.x, majorCell.y) - 0.8);
                float fade = exp(-centerDistance * 0.16);
                glow += frame.accent.rgb * (minorLine * 0.35 + majorLine * 1.1) * fade * material.tableSurface.w;
            }
            else {
                m.albedo = Marble(p * 0.22, material.tableColor.rgb, material.tableColor.rgb * 1.7, 6.0);
            }
            m.roughness = material.tableSurface.x;
            // The light falls on the board; the table darkens away from it.
            m.albedo *= mix(1.0, 0.18, smoothstep(material.tableFade.x, material.tableFade.y, centerDistance));
            m.occlusion = ContactShadow(p, material);
            // Darker under and around the board.
            float board = max(abs(p.x), abs(p.y));
            m.occlusion *= mix(0.35, 1.0, smoothstep(material.boardShape.z - 0.05, material.boardShape.z + 1.3, board));
            if (material.tableSurface.z > 0.0) {
                // The sheen of cloth at grazing angles.
                m.emissive += material.tableColor.rgb * material.tableSurface.z * pow(1.0 - saturate(dot(N, V)), 4.0) * 0.5;
            }
        }

        float spread = NormalSpread(N);
        m.roughness = WidenRoughness(m.roughness, spread);
        m.clearcoatRoughness = WidenRoughness(m.clearcoatRoughness, spread);
        float shadow = Shadow(in.world, N, in.position.xy, frame, shadowMap);
        float3 color = Shade(m, in.world, N, V, shadow, frame, irradiance, prefiltered, brdf) + glow;
        if (kind == 0) {
            float fresnel = mix(0.1, 1.0, pow(1.0 - saturate(dot(N, V)), 5.0));
            color = mix(color, planar.rgb, float3(planar.a * fresnel * material.boardReflection.x));
        }
        return float4(ApplyFog(color, in.world, frame), 1.0);
    }

    // The depth of the board, the bowls and the lids as the key light sees them.
    struct DepthVaryings {
        float4 position [[position]];
    };

    vertex DepthVaryings shadowSurfaceVertex(uint vid [[vertex_id]],
                                             const device SurfaceVertex* vertices [[buffer(0)]],
                                             constant SurfaceDraw& draw [[buffer(1)]],
                                             constant FrameData& frame [[buffer(2)]])
    {
        DepthVaryings out;
        out.position = frame.lightViewProjection * draw.model * float4(vertices[vid].position, 1.0);
        return out;
    }

    // The studio behind the table, out of focus.
    fragment float4 backgroundFragment(FullscreenVaryings in [[stage_in]],
                                       constant FrameData& frame [[buffer(0)]],
                                       texturecube<float> prefiltered [[texture(2)]])
    {
        float4 far = frame.inverseViewProjection * float4(in.ndc, 1.0, 1.0);
        float3 direction = normalize(far.xyz / far.w - frame.cameraPosition.xyz);
        float3 color = prefiltered.sample(linearClamp, direction, level(frame.environment.z * 0.6)).rgb * frame.environment.w;
        // Below the horizon the table fades into the fog.
        color = mix(color, frame.fog.rgb, float3(1.0 - smoothstep(-0.25, 0.02, direction.y)));
        return float4(color, 1.0);
    }
    """#
}

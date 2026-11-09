import Foundation

/// The stones as they lie and move: heaped in the bowls, flying from a bowl to the point played, the stones taken
/// flying into the lid of the player who took them, all of it in reverse when a move is taken back, and dissolving in
/// when a game is set out.
struct BoardView {
    /// What happened in a frame, for the sounds.
    enum Event: Comparable {
        case place
        case capture
        case returnToBowl
    }

    private enum Place {
        case board
        case bowl
        case lid
        case leaving
    }

    private struct Stone {
        var color = StoneColor.black
        var place = Place.bowl
        var point = Go.pass        // on the board
        var lid = -1, slot = 0     // in a lid: whose, and its place there
        var position = Vec3.zero   // the middle of the stone
        var yaw: Float = 0, seed: Float = 0
        var tiltAxis = Vec3(1, 0, 0) // how it lies, leaning on the stones under it
        var tilt: Float = 0
        // A flight from one place to another, in an arc, turning from one tilt to another.
        var from = Vec3.zero, to = Vec3.zero
        var fromAxis = Vec3(1, 0, 0)
        var fromTilt: Float = 0
        var flightTime: Float = 0, flightDuration: Float = 0, flightDelay: Float = 0, arc: Float = 0
        var flying = false
        var removeWhenLanded = false
        var landing = Event.place
        var dissolve: Float = 0, dissolveTarget: Float = 0, dissolveDelay: Float = 0
        var removeWhenGone = false
        var lift: Float = 0, liftTarget: Float = 0 // in the preview of a capture

        /// A stone already on its way starts again from where it is, with the lean of the end it is nearer.
        mutating func fly(to target: Vec3, tilt newTilt: Float, axis: Vec3, duration: Float, arc newArc: Float, delay: Float, landing event: Event) {
            let nearerStart = flying && (flightDelay > 0 || flightTime < flightDuration * 0.5)
            if !nearerStart {
                fromAxis = tiltAxis
                fromTilt = tilt
            }
            from = position
            to = target
            tiltAxis = axis
            tilt = newTilt
            flightTime = 0
            flightDuration = duration
            flightDelay = delay
            arc = newArc
            flying = true
            landing = event
        }
    }

    private static let fadeTime: Float = 0.45
    private static let heapLayer: Float = 0.24 // between the layers of stones in a bowl
    private static let lidLayer: Float = 0.2   // and in a lid
    private static let spacing: Float = 0.86   // between the stones lying side by side, a little leaning on each other

    private var layout = BoardLayout(size: 19)
    private var stones: [Stone] = []
    private var lidCounts = [0, 0]
    private var seed: UInt32 = 1

    // MARK: Setting out

    /// The places of the bowls and the lids for a size of board; the heaps in the bowls are made again.
    mutating func setLayout(_ newLayout: BoardLayout) {
        layout = newLayout
        stones.removeAll()
        lidCounts = [0, 0]
        buildHeaps()
    }

    /// Sets out the game's position on the board, and the stones taken in the lids.
    mutating func rebuild(_ game: Game, animate: Bool) {
        // The stones on the board and in the lids go; the heaps in the bowls stay.
        for index in stones.indices where stones[index].place != .bowl {
            stones[index].place = .leaving
            stones[index].point = Go.pass
            stones[index].flying = false
            stones[index].removeWhenLanded = false
            stones[index].dissolveTarget = 1
            stones[index].dissolveDelay = 0
            stones[index].removeWhenGone = true
        }
        if !animate {
            stones.removeAll { $0.place == .leaving }
        }

        let position = game.current
        let size = position.size
        for y in 0..<size {
            for x in 0..<size {
                let point = Go.point(x, y)
                guard position.isStone(point) else { continue }
                let color: StoneColor = position.cell(at: point) == .black ? .black : .white
                let index = add(color, .board, onBoard(point), appear: animate, delay: 0.25 + 0.0035 * Float(x + y * size))
                stones[index].point = point
            }
        }
        for lid in 0..<2 {
            let owner: StoneColor = lid == 0 ? .black : .white
            let count = position.captures(by: owner)
            for slot in 0..<count {
                let (place, tilt, axis) = lidSlot(lid, slot)
                let index = add(owner.opposite, .lid, place, appear: animate, delay: 0.4 + 0.01 * Float(slot))
                stones[index].lid = lid
                stones[index].slot = slot
                stones[index].tilt = tilt
                stones[index].tiltAxis = axis
            }
            lidCounts[lid] = count
        }
    }

    /// A move played (forward) or taken back.
    mutating func playMove(_ record: MoveRecord, forward: Bool) {
        guard !record.isPass && !record.isResignation else { return }
        let bowl = record.color.index
        let lid = bowl // a player keeps the stones taken in the lid of their own bowl
        let target = onBoard(record.point)
        let returning = record.captured.sorted { (onBoard($0) - target).length < (onBoard($1) - target).length }

        if forward {
            // A stone from the player's bowl flies to the point.
            let start = heapTop(bowl)
            let index = add(record.color, .board, start, appear: false, delay: 0)
            stones[index].point = record.point
            stones[index].tiltAxis = randomAxis()
            stones[index].tilt = 0.3
            let distance = (target - start).length
            let duration = min(0.4 + 0.012 * distance, 0.68)
            stones[index].fly(to: target, tilt: 0, axis: Vec3(1, 0, 0), duration: duration, arc: 0.9 + 0.035 * distance, delay: 0, landing: .place)

            // Then the stones it takes fly into the lid, the nearest first.
            var delay = duration + 0.08
            for point in returning {
                if let taken = onPoint(point) {
                    toLid(taken, lid: lid, delay: delay)
                    delay += 0.045
                }
            }
            return
        }

        // Back: the stone returns to its bowl, and the stones it took come back from the lid, the last put there first.
        if let index = onPoint(record.point) {
            stones[index].place = .leaving
            stones[index].point = Go.pass
            stones[index].removeWhenLanded = true
            let top = heapTop(bowl)
            let axis = randomAxis()
            stones[index].fly(to: top, tilt: 0.3, axis: axis, duration: 0.45, arc: 1, delay: 0, landing: .returnToBowl)
        }
        let inLid = stones.indices.filter { stones[$0].place == .lid && stones[$0].lid == lid }.sorted { stones[$0].slot > stones[$1].slot }
        var movers: [Int] = []
        for i in returning.indices {
            if i < inLid.count {
                movers.append(inLid[i])
            } else {
                let (place, _, _) = lidSlot(lid, 0)
                movers.append(add(record.color.opposite, .lid, place, appear: false, delay: 0))
            }
        }
        var delay: Float = 0.08
        for (i, point) in returning.enumerated() {
            let index = movers[i]
            stones[index].place = .board
            stones[index].point = point
            stones[index].lid = -1
            stones[index].fly(to: onBoard(point), tilt: 0, axis: Vec3(1, 0, 0), duration: 0.55, arc: 1.3, delay: delay, landing: .place)
            delay += 0.04
        }
        lidCounts[lid] = max(0, lidCounts[lid] - returning.count)
    }

    /// The stones that a stone placed under the pointer would take glow and rise a little, about to go.
    mutating func preview(_ taking: [GoPoint]) {
        for index in stones.indices {
            let stone = stones[index]
            stones[index].liftTarget = stone.place == .board && !stone.flying && taking.contains(stone.point) ? 1 : 0
        }
    }

    mutating func update(_ seconds: Float, events: inout [Event]) {
        for index in stones.indices {
            stones[index].lift = Self.approach(stones[index].lift, stones[index].liftTarget, seconds / 0.15)
            if stones[index].dissolveDelay > 0 {
                stones[index].dissolveDelay -= seconds
            } else {
                stones[index].dissolve = Self.approach(stones[index].dissolve, stones[index].dissolveTarget, seconds / Self.fadeTime)
            }

            guard stones[index].flying else { continue }
            if stones[index].flightDelay > 0 {
                stones[index].flightDelay -= seconds
                continue
            }
            var stone = stones[index]
            stone.flightTime = min(stone.flightTime + seconds, stone.flightDuration)
            let t = stone.flightTime / stone.flightDuration
            stone.position = lerp(stone.from, stone.to, Self.ease(t)) + Vec3(0, stone.arc * sin(.pi * t), 0)
            if t >= 1 {
                stone.position = stone.to
                stone.flying = false
                events.append(stone.landing)
            }
            stones[index] = stone
        }
        stones.removeAll { ($0.removeWhenGone && $0.dissolve >= 1) || ($0.removeWhenLanded && !$0.flying) }
    }

    /// Nothing flying or dissolving: the position shown is the game's.
    var isSettled: Bool { !stones.contains { $0.flying || $0.dissolve != $0.dissolveTarget } }

    /// The stones of the board in their places, though stones taken may still be on their way to a lid.
    var isBoardReady: Bool { !stones.contains { $0.place == .board && ($0.flying || $0.dissolve != $0.dissolveTarget) } }

    /// Stones about to be taken pulse while they are lifted.
    var isAnimating: Bool { !isSettled || stones.contains { $0.lift != $0.liftTarget || $0.lift > 0 } }

    // MARK: Drawing

    /// `dead` stones are drawn seen through; stones about to be taken glow in `warning`.
    func draws(lastMove: GoPoint, dead: [Bool]?, warning: Vec3, time: Float) -> [StoneDraw] {
        stones.map { stone in
            var orientation = Mat4.rotation(axis: stone.tiltAxis, angle: stone.tilt)
            if stone.flying && stone.flightDelay > 0 {
                orientation = Mat4.rotation(axis: stone.fromAxis, angle: stone.fromTilt)
            } else if stone.flying {
                let e = Self.ease(stone.flightTime / stone.flightDuration)
                orientation = Mat4.rotation(axis: stone.tiltAxis, angle: e * stone.tilt) * Mat4.rotation(axis: stone.fromAxis, angle: (1 - e) * stone.fromTilt)
            }
            let resting = stone.place == .board && !stone.flying
            let lift = Self.ease(stone.lift) * (0.8 + 0.2 * sin(time * 6))
            var draw = StoneDraw()
            draw.model = Mat4.translation(stone.position + Vec3(0, 0.12 * lift, 0)) * orientation * Mat4.rotationY(stone.yaw)
            draw.white = stone.color == .white
            draw.ground = stone.flying ? groundAt(stone.position) : stone.position.y - StoneModel.halfHeight
            draw.dissolve = stone.dissolve
            draw.seed = stone.seed
            draw.glowColor = warning
            draw.glow = 1.5 * lift
            if resting && stone.point == lastMove {
                draw.mark = 1
            }
            if resting, let dead, dead[stone.point] {
                draw.opacity = 0.42
            }
            return draw
        }
    }

    /// The points with a stone lying on them, for the shade round the stones.
    func markStones(_ marks: inout [UInt8]) {
        for stone in stones where stone.place == .board && !stone.flying && stone.dissolve < 0.5 {
            marks[Go.x(stone.point) + Go.maxSize * Go.y(stone.point)] |= SceneMark.stoneHere
        }
    }

    // MARK: Places

    private mutating func add(_ color: StoneColor, _ place: Place, _ position: Vec3, appear: Bool, delay: Float) -> Int {
        var stone = Stone()
        stone.color = color
        stone.place = place
        stone.position = position
        stone.yaw = random() * 2 * .pi
        stone.seed = random()
        if appear {
            stone.dissolve = 1
            stone.dissolveDelay = delay
        }
        stones.append(stone)
        return stones.count - 1
    }

    private func onPoint(_ point: GoPoint) -> Int? {
        stones.firstIndex { $0.place == .board && $0.point == point }
    }

    private func onBoard(_ point: GoPoint) -> Vec3 {
        layout.center(of: point) + Vec3(0, StoneModel.halfHeight, 0)
    }

    private func groundAt(_ position: Vec3) -> Float {
        abs(position.x) < layout.boardHalf && abs(position.z) < layout.boardHalf ? 0 : layout.tableHeight
    }

    /// Each bowl holds a heap of its stones: a few layers, the stones leaning on each other, higher in the middle.
    private mutating func buildHeaps() {
        let reach = 0.72 * layout.bowlRadius - 0.48
        for bowl in 0..<2 {
            let base = layout.bowls[bowl]
            let floor = BoardLayout.heapHeight(height: layout.bowlHeight) - 0.05 // above the foot of the bowl
            let color: StoneColor = bowl == 0 ? .black : .white
            for layer in 0..<3 {
                let layerReach = reach * (1 - 0.32 * Float(layer))
                let shift = layer == 1 ? Self.spacing * 0.5 : 0
                let count = Int((layerReach / Self.spacing).rounded(.up)) + 1
                for row in -count...count {
                    for column in -count...count {
                        var x = (Float(column) + 0.5 * Float(row & 1)) * Self.spacing + shift
                        var z = Float(row) * Self.spacing * 0.866 + shift * 0.577
                        x += (random() - 0.5) * 0.16
                        z += (random() - 0.5) * 0.16
                        let r2 = x * x + z * z
                        if r2 > layerReach * layerReach {
                            continue
                        }
                        let dome = 0.12 * (1 - r2 / max(reach * reach, 0.01))
                        let y = floor + StoneModel.halfHeight + Float(layer) * Self.heapLayer + dome
                        let index = add(color, .bowl, base + Vec3(x, y, z), appear: false, delay: 0)
                        stones[index].tiltAxis = randomAxis()
                        stones[index].tilt = 0.1 + 0.3 * random()
                    }
                }
            }
        }
    }

    /// Where a stone is taken from a bowl and put back into it: the top of the heap.
    private mutating func heapTop(_ bowl: Int) -> Vec3 {
        let base = layout.bowls[bowl]
        let angle = random() * 2 * .pi, radius = 0.35 * random().squareRoot()
        let top = BoardLayout.heapHeight(height: layout.bowlHeight) - 0.05 + StoneModel.halfHeight + 2 * Self.heapLayer + 0.12
        return base + Vec3(cos(angle) * radius, top, sin(angle) * radius)
    }

    /// The stones taken lie in the lid in a spiral, as many as fit on its floor, and then in smaller layers on top.
    private func lidSlot(_ lid: Int, _ slot: Int) -> (place: Vec3, tilt: Float, axis: Vec3) {
        let reach = 0.84 * layout.bowlRadius - 0.5
        var index = slot, layer = 0
        var layerReach = reach
        var capacity = 0
        while true {
            layerReach = reach * max(0.3, 1 - 0.2 * Float(layer))
            capacity = max(3, Int(0.85 * (layerReach / 0.5) * (layerReach / 0.5)))
            if index < capacity {
                break
            }
            index -= capacity
            layer += 1
        }
        let radius = layerReach * ((Float(index) + 0.5) / Float(capacity)).squareRoot()
        let angle = Float(index) * 2.39996 + Float(layer) * 1.3
        let jitter = 0.08 * (Self.hash(lid * 977 + 1, slot) - 0.5)
        let base = layout.lids[lid]
        let tilt = 0.05 + 0.15 * Self.hash(lid * 977 + 2, slot) + (layer > 0 ? 0.1 : 0)
        let axisAngle = 2 * .pi * Self.hash(lid * 977 + 3, slot)
        let y = BoardLayout.lidFloor(radius: layout.bowlRadius) + StoneModel.halfHeight + Float(layer) * Self.lidLayer
        return (base + Vec3(cos(angle) * (radius + jitter), y, sin(angle) * (radius + jitter)), tilt, Vec3(cos(axisAngle), 0, sin(axisAngle)))
    }

    private mutating func toLid(_ index: Int, lid: Int, delay: Float) {
        let slot = lidCounts[lid]
        lidCounts[lid] += 1
        let (place, tilt, axis) = lidSlot(lid, slot)
        stones[index].place = .lid
        stones[index].point = Go.pass
        stones[index].lid = lid
        stones[index].slot = slot
        stones[index].fly(to: place, tilt: tilt, axis: axis, duration: 0.62, arc: 1.5, delay: delay, landing: .capture)
    }

    // MARK: Numbers

    private mutating func random() -> Float {
        seed = seed &* 1_664_525 &+ 1_013_904_223
        return Float(seed >> 8) / Float(1 << 24)
    }

    private mutating func randomAxis() -> Vec3 {
        let angle = random() * 2 * .pi
        return Vec3(cos(angle), 0, sin(angle))
    }

    private static func ease(_ t: Float) -> Float { t * t * t * (t * (t * 6 - 15) + 10) }

    private static func approach(_ value: Float, _ target: Float, _ step: Float) -> Float {
        value < target ? min(value + step, target) : max(value - step, target)
    }

    /// A number in [0, 1) that stays the same for the same arguments.
    private static func hash(_ a: Int, _ b: Int) -> Float {
        var h = UInt32(truncatingIfNeeded: a) &* 0x9E37_79B1 ^ UInt32(truncatingIfNeeded: b) &* 0x85EB_CA77
        h ^= h >> 15
        h = h &* 0x2C1B_3C6D
        h ^= h >> 12
        return Float(h >> 8) / Float(1 << 24)
    }
}

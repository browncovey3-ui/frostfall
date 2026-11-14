import SpriteKit
import AppKit

private struct Flake {
    var x: CGFloat = 0
    var y: CGFloat = 0
    var vy: CGFloat = 0
    var size: CGFloat = 0
    var phase: CGFloat = 0
    var sway: CGFloat = 0
    var swaySpeed: CGFloat = 0
    var drift: CGFloat = 0
    var lands = false
    let node: SKSpriteNode
}

/// Snow that has been knocked loose: spray from the cursor, or lumps falling off a window.
private struct Debris {
    var x: CGFloat
    var y: CGFloat
    var vx: CGFloat
    var vy: CGFloat
    var area: CGFloat
    var lump: Bool
    var age: CGFloat = 0
    let node: SKSpriteNode
}

/// One display's worth of snow.
final class SnowScene: SKScene {
    /// Global AppKit origin of the display this scene covers.
    var screenOrigin: CGPoint = .zero
    /// Height of the menu bar area at the top of this display.
    var topInset: CGFloat = 0

    private let root = SKNode()
    private var texture: SKTexture?
    private var flakes: [Flake] = []
    private var debris: [Debris] = []
    private var ground: Surface?
    private var windowSurfaces: [CGWindowID: Surface] = [:]

    private var lastTime: TimeInterval = 0
    private var clock: CGFloat = 0
    private var frameCount = 0
    private var lastPoll: TimeInterval = 0
    private var lastWindowMotion: TimeInterval = 0
    private var lastMouse: CGPoint?

    private let maxDebris = 900

    // MARK: Setup

    override func didMove(to view: SKView) {
        backgroundColor = .clear
        if root.parent == nil { addChild(root) }
        if texture == nil { texture = SnowScene.makeTexture() }
    }

    private static func makeTexture() -> SKTexture {
        let side: CGFloat = 32
        let gradient = NSGradient(colorsAndLocations:
            (NSColor(calibratedWhite: 1, alpha: 1), 0.0),
            (NSColor(calibratedWhite: 1, alpha: 0.85), 0.4),
            (NSColor(calibratedWhite: 1, alpha: 0), 1.0))
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            gradient?.draw(in: NSBezierPath(ovalIn: rect), relativeCenterPosition: NSPoint.zero)
            return true
        }
        return SKTexture(image: image)
    }

    private func makeSprite(z: CGFloat) -> SKSpriteNode {
        let node = SKSpriteNode(texture: texture)
        node.zPosition = z
        root.addChild(node)
        return node
    }

    private func ensureGround() {
        let columns = Int((size.width / columnWidth).rounded(.up))
        if let g = ground, g.heights.count == columns { return }
        ground?.node.removeFromParent()
        let g = Surface(x: 0, y: 0, columns: columns,
                        maxHeight: min(90, max(30, size.height * 0.1)),
                        meltRate: 0.0025, taperEdges: false)
        root.addChild(g.node)
        ground = g
    }

    private func syncFlakeCount() {
        let s = Settings.shared
        let areaScale = max(0.3, (size.width * size.height) / (1440 * 900))
        let t = pow(max(0, min(1, s.intensity)), 1.5)
        let target = min(2600, Int((50 + 1350 * t) * areaScale))
        if flakes.count < target {
            // Add gradually so a big jump does not stall a frame.
            let add = min(target - flakes.count, 120)
            for _ in 0..<add {
                var f = Flake(node: makeSprite(z: 1))
                respawn(&f, anywhere: true)
                f.node.position = CGPoint(x: f.x, y: f.y)
                flakes.append(f)
            }
        } else if flakes.count > target {
            let remove = min(flakes.count - target, 120)
            for _ in 0..<remove {
                flakes.removeLast().node.removeFromParent()
            }
        }
    }

    private func respawn(_ f: inout Flake, anywhere: Bool) {
        let raw = CGFloat.random(in: 0...1)
        let d = raw * raw // most flakes are small and far away
        f.size = 1.6 + d * 4.2
        f.vy = 28 + d * 75 + CGFloat.random(in: 0...12)
        f.x = CGFloat.random(in: 0...max(1, size.width))
        f.y = anywhere ? CGFloat.random(in: 0...max(1, size.height))
                       : size.height + CGFloat.random(in: 4...60)
        f.phase = CGFloat.random(in: 0...(2 * CGFloat.pi))
        f.sway = 6 + d * 16
        f.swaySpeed = CGFloat.random(in: 0.5...1.4)
        f.drift = 0.4 + d * 0.8
        f.lands = raw > 0.5
        f.node.size = CGSize(width: f.size * 2, height: f.size * 2)
        f.node.alpha = 0.45 + d * 0.55
    }

    // MARK: Public controls

    func clearSnow() {
        ground?.clear()
        for sf in windowSurfaces.values { sf.clear() }
        for d in debris { d.node.removeFromParent() }
        debris.removeAll()
    }

    /// Drops all window ledges without animation (used when switching Spaces).
    func forgetWindows() {
        for sf in windowSurfaces.values { sf.node.removeFromParent() }
        windowSurfaces.removeAll()
    }

    // MARK: Frame loop

    override func update(_ currentTime: TimeInterval) {
        var dt: CGFloat = 1.0 / 60.0
        if lastTime > 0 { dt = CGFloat(min(max(currentTime - lastTime, 0.001), 0.05)) }
        lastTime = currentTime
        clock += dt
        frameCount += 1

        let s = Settings.shared
        root.alpha = max(0.1, min(1, s.opacity))
        ensureGround()
        syncFlakeCount()

        if s.settleOnWindows {
            let interval: TimeInterval = (currentTime - lastWindowMotion < 1.0) ? 1.0 / 30.0 : 1.0 / 8.0
            if currentTime - lastPoll >= interval {
                let elapsed = CGFloat(min(currentTime - lastPoll, 0.25))
                lastPoll = currentTime
                syncWindows(WindowTracker.snapshot(), elapsed: elapsed, now: currentTime)
            }
        } else if !windowSurfaces.isEmpty {
            forgetWindows()
        }

        updateFlakes(dt: dt, groundOn: s.settleOnGround)
        sweep(dt: dt)
        updateDebris(dt: dt, groundOn: s.settleOnGround)

        let melt = s.melt
        if let g = ground { maintain(g, dt: dt, melt: melt, every: 4) }
        for sf in windowSurfaces.values { maintain(sf, dt: dt, melt: melt, every: 3) }
    }

    private func maintain(_ sf: Surface, dt: CGFloat, melt: Bool, every: Int) {
        if melt { sf.melt(dt) }
        if sf.needsRelax { sf.relax() }
        if sf.dirty && frameCount % every == 0 { sf.rebuildPath() }
    }

    private func updateFlakes(dt: CGFloat, groundOn: Bool) {
        let wind = 16 * sin(clock * 0.11) + 8 * sin(clock * 0.31 + 1.7)
        let width = size.width
        let ledges = Array(windowSurfaces.values)
        let g = ground

        for idx in flakes.indices {
            var f = flakes[idx]
            let oldY = f.y
            f.y -= f.vy * dt
            f.x += (wind * f.drift + sin(f.phase + clock * f.swaySpeed) * f.sway) * dt
            if f.x < -10 { f.x += width + 20 } else if f.x > width + 10 { f.x -= width + 20 }

            var landed = false
            if f.lands {
                for sf in ledges {
                    if oldY < sf.y || f.y > sf.y + sf.maxHeight { continue }
                    guard let i = sf.column(at: f.x), !sf.blocked[i] else { continue }
                    let top = sf.y + sf.heights[i]
                    if oldY >= top && f.y < top {
                        sf.deposit(at: i, area: (0.5 + f.size * 0.35) * 2.0)
                        landed = true
                        break
                    }
                }
            }
            if !landed, groundOn, let g = g, f.y < g.maxHeight + 1,
               let i = g.column(at: f.x), f.y <= g.heights[i] {
                g.deposit(at: i, area: 0.5 + f.size * 0.35)
                landed = true
            }
            if landed || f.y < -8 { respawn(&f, anywhere: false) }
            f.node.position = CGPoint(x: f.x, y: f.y)
            flakes[idx] = f
        }
    }

    // MARK: Loose snow

    private func spawnDebris(x: CGFloat, y: CGFloat, vx: CGFloat, vy: CGFloat, area: CGFloat, lump: Bool) {
        guard debris.count < maxDebris else { return }
        let node = makeSprite(z: 3)
        let s: CGFloat = lump ? min(9, 2.5 + area.squareRoot()) : min(5, 1.5 + area.squareRoot() * 0.6)
        node.size = CGSize(width: s * 2, height: s * 2)
        node.alpha = 0.95
        node.position = CGPoint(x: x, y: y)
        debris.append(Debris(x: x, y: y, vx: vx, vy: vy, area: area, lump: lump, node: node))
    }

    private func updateDebris(dt: CGFloat, groundOn: Bool) {
        let width = size.width
        var i = 0
        while i < debris.count {
            var d = debris[i]
            d.age += dt
            d.vy = max(-900, d.vy - 700 * dt)
            d.vx *= max(0, 1 - 1.2 * dt)
            d.x += d.vx * dt
            d.y += d.vy * dt

            var done = d.age > 8 || d.y < -12 || d.x < -40 || d.x > width + 40
            if !done, d.vy < 0, let g = ground, let gi = g.column(at: d.x), d.y <= g.heights[gi] + 1 {
                if groundOn { g.deposit(at: gi, area: d.area) }
                if d.lump {
                    for _ in 0..<4 {
                        spawnDebris(x: d.x, y: d.y + 2,
                                    vx: CGFloat.random(in: -70...70),
                                    vy: CGFloat.random(in: 40...140),
                                    area: 0, lump: false)
                    }
                }
                done = true
            }

            if done {
                d.node.removeFromParent()
                debris[i] = debris[debris.count - 1]
                debris.removeLast()
            } else {
                d.node.position = CGPoint(x: d.x, y: d.y)
                debris[i] = d
                i += 1
            }
        }
    }

    /// Knocks a fraction of a ledge's snow loose so it falls.
    private func shed(_ sf: Surface, fraction: CGFloat, lumps: Bool) {
        let n = sf.heights.count
        let step = lumps ? 5 : 4
        var i = 0
        while i < n {
            let end = min(n, i + step)
            var area: CGFloat = 0
            var visible = false
            for k in i..<end {
                let take = sf.heights[k] * fraction
                sf.heights[k] -= take
                area += take * columnWidth
                if !sf.blocked[k] { visible = true }
            }
            if area > 0.8 && visible {
                let cx = sf.x + CGFloat(i + end) * 0.5 * columnWidth
                spawnDebris(x: cx, y: sf.y + 2,
                            vx: CGFloat.random(in: -25...25),
                            vy: CGFloat.random(in: -10...40),
                            area: area, lump: lumps)
            }
            i = end
        }
        sf.dirty = true
    }

    // MARK: Cursor

    private func sweep(dt: CGFloat) {
        let global = NSEvent.mouseLocation
        let p = CGPoint(x: global.x - screenOrigin.x, y: global.y - screenOrigin.y)
        defer { lastMouse = p }
        guard let last = lastMouse else { return }
        let dx = p.x - last.x, dy = p.y - last.y
        guard abs(dx) + abs(dy) > 0.5 else { return }
        guard p.x > -20, p.x < size.width + 20, p.y > -20, p.y < size.height + 20 else { return }
        let vx = max(-1500, min(1500, dx / dt))
        let vy = max(-1500, min(1500, dy / dt))
        if let g = ground { carve(g, at: p, vx: vx, vy: vy) }
        for sf in windowSurfaces.values { carve(sf, at: p, vx: vx, vy: vy) }
    }

    private func carve(_ sf: Surface, at p: CGPoint, vx: CGFloat, vy: CGFloat) {
        let r: CGFloat = 14
        guard p.y + r > sf.y, p.y - r < sf.y + sf.maxHeight else { return }
        let n = sf.heights.count
        let i0 = max(0, Int(((p.x - r - sf.x) / columnWidth).rounded(.down)))
        let i1 = min(n - 1, Int(((p.x + r - sf.x) / columnWidth).rounded(.up)))
        guard i0 <= i1 else { return }

        var removed: CGFloat = 0
        for i in i0...i1 where !sf.blocked[i] {
            let cx = sf.x + (CGFloat(i) + 0.5) * columnWidth
            let ddx = cx - p.x
            guard abs(ddx) < r else { continue }
            let floorY = max(0, p.y - (r * r - ddx * ddx).squareRoot() - sf.y)
            if sf.heights[i] > floorY {
                removed += (sf.heights[i] - floorY) * columnWidth
                sf.heights[i] = floorY
            }
        }
        guard removed > 0 else { return }
        sf.dirty = true
        sf.needsRelax = true

        // Plough half of it ahead of the cursor, throw the rest into the air.
        if abs(vx) > 30 {
            let dir = vx >= 0 ? 1 : -1
            if let j = sf.column(at: p.x + CGFloat(dir) * (r + 3)) {
                let share = removed * 0.5 / 4
                for k in 0..<4 { sf.deposit(at: j + dir * k * 2, area: share) }
                removed *= 0.5
            }
        }
        var left = removed
        var count = 0
        while left > 0.5 && count < 12 {
            let a = min(left, 4)
            left -= a
            count += 1
            spawnDebris(x: p.x + CGFloat.random(in: -r...r) * 0.6,
                        y: max(p.y - r * 0.5, sf.y + 1),
                        vx: vx * 0.25 + CGFloat.random(in: -80...80),
                        vy: 90 + CGFloat.random(in: 0...160) + max(0, vy) * 0.15,
                        area: a, lump: false)
        }
    }

    // MARK: Windows

    private func syncWindows(_ list: [TrackedWindow], elapsed: CGFloat, now: TimeInterval) {
        let inset: CGFloat = 12 // keep clear of rounded corners
        let ledgeMax: CGFloat = 13
        let bounds = CGRect(origin: .zero, size: size)
        var locals: [CGRect] = []
        locals.reserveCapacity(list.count)
        for w in list {
            locals.append(w.frame.offsetBy(dx: -screenOrigin.x, dy: -screenOrigin.y))
        }

        var seen = Set<CGWindowID>()
        for (idx, w) in list.enumerated() {
            let r = locals[idx]
            guard r.intersects(bounds) else { continue }
            let columns = Int((r.width - inset * 2) / columnWidth)
            guard columns >= 30 else { continue }
            seen.insert(w.id)
            let nx = r.minX + inset
            let ny = r.maxY

            let sf: Surface
            if let existing = windowSurfaces[w.id] {
                sf = existing
                let dx = nx - sf.x, dy = ny - sf.y
                if dx != 0 || dy != 0 {
                    lastWindowMotion = now
                    let speed = (dx * dx + dy * dy).squareRoot() / max(elapsed, 0.001)
                    let fraction = min(0.6, max(0, (speed - 200) / 2500))
                    if fraction > 0 { shed(sf, fraction: fraction, lumps: false) }
                    sf.move(toX: nx, y: ny)
                }
                if sf.heights.count != columns { sf.resize(columns: columns) }
            } else {
                sf = Surface(x: nx, y: ny, columns: columns, maxHeight: ledgeMax,
                             meltRate: 0.005, taperEdges: true)
                root.addChild(sf.node)
                windowSurfaces[w.id] = sf
            }

            // Work out where this top edge is hidden.
            let roomAbove = ny < size.height - topInset - 4 && ny > 30
            var blocked = [Bool](repeating: !roomAbove, count: columns)
            if roomAbove {
                for i in 0..<columns {
                    let px = nx + (CGFloat(i) + 0.5) * columnWidth
                    if px < 0 || px > size.width { blocked[i] = true }
                }
                for j in 0..<idx {
                    let front = locals[j]
                    guard front.minY < ny + ledgeMax, front.maxY > ny + 1 else { continue }
                    let a = max(0, Int(((front.minX - nx) / columnWidth).rounded(.down)))
                    let b = min(columns, Int(((front.maxX - nx) / columnWidth).rounded(.up)))
                    if a < b { for i in a..<b { blocked[i] = true } }
                }
            }
            if blocked != sf.blocked {
                sf.blocked = blocked
                sf.dirty = true
            }
        }

        for id in Array(windowSurfaces.keys) where !seen.contains(id) {
            if let sf = windowSurfaces[id] {
                shed(sf, fraction: 1, lumps: true)
                sf.node.removeFromParent()
            }
            windowSurfaces[id] = nil
        }
    }
}

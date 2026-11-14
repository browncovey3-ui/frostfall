import SpriteKit

/// Width in points of one column of a snow heightmap.
let columnWidth: CGFloat = 2

/// A ledge that snow can settle on: the bottom of the screen or the top edge of a window.
/// Snow depth is stored as a heightmap, one value per column.
final class Surface {
    var x: CGFloat
    var y: CGFloat
    var heights: [CGFloat]
    /// Columns where snow is hidden and cannot land (covered by another window, or off screen).
    var blocked: [Bool]
    let maxHeight: CGFloat
    let meltRate: CGFloat
    let taperEdges: Bool
    let node = SKShapeNode()
    var dirty = false
    var needsRelax = false
    private var meltClock: CGFloat = 0

    init(x: CGFloat, y: CGFloat, columns: Int, maxHeight: CGFloat, meltRate: CGFloat, taperEdges: Bool) {
        self.x = x
        self.y = y
        self.heights = [CGFloat](repeating: 0, count: max(columns, 0))
        self.blocked = [Bool](repeating: false, count: max(columns, 0))
        self.maxHeight = maxHeight
        self.meltRate = meltRate
        self.taperEdges = taperEdges
        node.fillColor = SKColor(calibratedWhite: 1, alpha: 0.97)
        node.strokeColor = SKColor(calibratedRed: 0.76, green: 0.84, blue: 0.93, alpha: 0.75)
        node.lineWidth = 1
        node.isAntialiased = true
        node.zPosition = 2
        node.position = CGPoint(x: x, y: y)
    }

    func column(at px: CGFloat) -> Int? {
        let i = Int(((px - x) / columnWidth).rounded(.down))
        return (i >= 0 && i < heights.count) ? i : nil
    }

    func move(toX nx: CGFloat, y ny: CGFloat) {
        x = nx
        y = ny
        node.position = CGPoint(x: nx, y: ny)
    }

    func resize(columns n: Int) {
        let n = max(n, 0)
        if n < heights.count {
            heights.removeLast(heights.count - n)
            blocked.removeLast(blocked.count - n)
        } else if n > heights.count {
            heights.append(contentsOf: [CGFloat](repeating: 0, count: n - heights.count))
            blocked.append(contentsOf: [Bool](repeating: false, count: n - blocked.count))
        }
        dirty = true
    }

    /// Adds area square points of snow centred on column i.
    func deposit(at i: Int, area: CGFloat) {
        guard area > 0 else { return }
        let h = area / columnWidth
        add(i, h * 0.5)
        add(i - 1, h * 0.25)
        add(i + 1, h * 0.25)
        dirty = true
        needsRelax = true
    }

    private func add(_ i: Int, _ h: CGFloat) {
        guard i >= 0 && i < heights.count else { return }
        heights[i] = min(maxHeight, heights[i] + h)
    }

    func clear() {
        for i in heights.indices { heights[i] = 0 }
        dirty = true
        needsRelax = false
    }

    /// Lets steep piles slump towards a natural slope.
    func relax() {
        let n = heights.count
        guard n > 2 else { needsRelax = false; return }
        let maxDiff = columnWidth * 1.1
        let taper = taperEdges
        var moved = false
        heights.withUnsafeMutableBufferPointer { h in
            var i = 0
            while i < n - 1 {
                let d = h[i] - h[i + 1]
                if d > maxDiff {
                    let m = (d - maxDiff) * 0.3
                    h[i] -= m; h[i + 1] += m
                    if m > 0.02 { moved = true }
                } else if d < -maxDiff {
                    let m = (-d - maxDiff) * 0.3
                    h[i] += m; h[i + 1] -= m
                    if m > 0.02 { moved = true }
                }
                i += 1
            }
            i = n - 1
            while i > 0 {
                let d = h[i] - h[i - 1]
                if d > maxDiff {
                    let m = (d - maxDiff) * 0.3
                    h[i] -= m; h[i - 1] += m
                    if m > 0.02 { moved = true }
                }
                i -= 1
            }
            if taper {
                if h[0] > 1 { h[0] = 1; moved = true }
                if h[n - 1] > 1 { h[n - 1] = 1; moved = true }
            }
        }
        if moved { dirty = true }
        needsRelax = moved
    }

    func melt(_ dt: CGFloat) {
        let rate = meltRate
        var any = false
        heights.withUnsafeMutableBufferPointer { h in
            for i in 0..<h.count where h[i] > 0 {
                h[i] = max(0, h[i] - (0.004 + rate * h[i]) * dt)
                any = true
            }
        }
        guard any else { return }
        meltClock += dt
        if meltClock > 0.5 {
            meltClock = 0
            dirty = true
        }
    }

    func rebuildPath() {
        dirty = false
        let path = CGMutablePath()
        let n = heights.count
        let threshold: CGFloat = 0.3
        var any = false
        var i = 0
        while i < n {
            if blocked[i] || heights[i] < threshold { i += 1; continue }
            var j = i
            while j < n && !blocked[j] && heights[j] >= threshold { j += 1 }
            path.move(to: CGPoint(x: CGFloat(i) * columnWidth, y: 0))
            for k in i..<j {
                path.addLine(to: CGPoint(x: (CGFloat(k) + 0.5) * columnWidth, y: heights[k]))
            }
            path.addLine(to: CGPoint(x: CGFloat(j) * columnWidth, y: 0))
            path.closeSubpath()
            any = true
            i = j
        }
        node.path = any ? path : nil
    }
}

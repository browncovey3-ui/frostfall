import AppKit

/// An ordinary on-screen window, in global AppKit coordinates (origin bottom-left of the primary display).
struct TrackedWindow {
    let id: CGWindowID
    let frame: CGRect
}

/// Reads the positions of other apps' windows. Only bounds, layer and owner are used,
/// none of which need Screen Recording permission.
enum WindowTracker {
    private static var cache: [TrackedWindow] = []
    private static var cacheTime: TimeInterval = 0

    /// Windows ordered front to back.
    static func snapshot() -> [TrackedWindow] {
        let now = ProcessInfo.processInfo.systemUptime
        if now - cacheTime < 0.012 { return cache }
        cacheTime = now

        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            cache = []
            return cache
        }
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let me = Int32(ProcessInfo.processInfo.processIdentifier)
        var result: [TrackedWindow] = []
        result.reserveCapacity(list.count)

        for info in list {
            guard let layer = (info[kCGWindowLayer as String] as? NSNumber)?.intValue, layer == 0 else { continue }
            guard let pid = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value, pid != me else { continue }
            guard let number = (info[kCGWindowNumber as String] as? NSNumber)?.uint32Value else { continue }
            if let alpha = (info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue, alpha < 0.05 { continue }
            guard let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
                  let b = CGRect(dictionaryRepresentation: boundsDict as CFDictionary) else { continue }
            guard b.width >= 120, b.height >= 60 else { continue }
            // Quartz window bounds use a top-left origin; flip to AppKit's bottom-left.
            let frame = CGRect(x: b.minX, y: primaryHeight - b.minY - b.height, width: b.width, height: b.height)
            result.append(TrackedWindow(id: CGWindowID(number), frame: frame))
        }
        cache = result
        return result
    }
}

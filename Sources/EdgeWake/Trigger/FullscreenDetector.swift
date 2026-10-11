import AppKit

/// Whether the frontmost app covers the whole display under the pointer, as a full-screen game or
/// video does. Window bounds and owners are readable without Screen Recording permission.
enum FullscreenDetector {
    @MainActor
    static func frontmostAppIsFullscreen() -> Bool {
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier,
              let primary = NSScreen.screens.first,
              let screen = NSScreen.screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }),
              let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else { return false }

        // Window bounds use a top-left origin on the primary display.
        let frame = screen.frame
        let target = CGRect(x: frame.minX, y: primary.frame.maxY - frame.maxY, width: frame.width, height: frame.height)
        return windows.contains { window in
            guard window[kCGWindowOwnerPID as String] as? pid_t == pid,
                  window[kCGWindowLayer as String] as? Int == 0,
                  let boundsDictionary = window[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDictionary as CFDictionary)
            else { return false }
            // On a display with a camera housing, full-screen windows stop below it by default.
            let notch = screen.safeAreaInsets.top
            return abs(bounds.width - target.width) < 1 && abs(bounds.maxY - target.maxY) < 1
                && abs(bounds.minY - target.minY) <= notch + 1
        }
    }
}

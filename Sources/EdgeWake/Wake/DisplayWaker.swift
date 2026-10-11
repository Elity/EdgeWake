import Foundation
import IOKit.pwr_mgt

/// Turns this Mac's display on, the same way `caffeinate -u` does: by declaring local user
/// activity. Works at the lock screen and needs no permission.
enum DisplayWaker {
    static func wake() {
        var assertion = IOPMAssertionID(0)
        let result = IOPMAssertionDeclareUserActivity("EdgeWake: woken by a paired Mac" as CFString, kIOPMUserActiveLocal, &assertion)
        guard result == kIOReturnSuccess else {
            NSLog("EdgeWake: could not wake the display (\(result))")
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            IOPMAssertionRelease(assertion)
        }
    }
}

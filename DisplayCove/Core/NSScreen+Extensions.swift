import Cocoa

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        guard
            let screenNumber = deviceDescription[
                NSDeviceDescriptionKey(rawValue: "NSScreenNumber")
            ] as? NSNumber
        else {
            return nil
        }

        return CGDirectDisplayID(screenNumber.uint32Value)
    }
}

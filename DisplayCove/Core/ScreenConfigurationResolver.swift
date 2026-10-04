import AppKit

protocol ScreenConfigurationProviding {
    var displayID: CGDirectDisplayID? { get }
    var frame: CGRect { get }
    var backingScaleFactor: CGFloat { get }
}

extension NSScreen: ScreenConfigurationProviding {}

struct ScreenConfigurationSnapshot: Equatable {
    let resolution: CGSize
    let scaleFactor: CGFloat
}

enum ScreenConfigurationResolver {
    static func configuration<Screens: Sequence>(
        for displayID: CGDirectDisplayID,
        screens: Screens
    ) -> ScreenConfigurationSnapshot? where Screens.Element: ScreenConfigurationProviding {
        guard let screen = screens.first(where: { $0.displayID == displayID }) else {
            return nil
        }

        return ScreenConfigurationSnapshot(
            resolution: screen.frame.size,
            scaleFactor: screen.backingScaleFactor
        )
    }
}

import CoreGraphics
import Darwin
import Foundation

@MainActor
struct DisplayHDRState {
    private let enabledDisplayIDs: [CGDirectDisplayID]
    private static let coreDisplay = CoreDisplayFunctions.load()

    static func capture() -> DisplayHDRState? {
        guard
            let coreDisplay,
            let displayIDs = onlineDisplayIDs()
        else {
            return nil
        }

        return DisplayHDRState(
            enabledDisplayIDs: displayIDs.filter(coreDisplay.isHDREnabled)
        )
    }

    func restoreAfterDisplayChange() {
        guard !enabledDisplayIDs.isEmpty else {
            return
        }

        for delay in [0.25, 1.0] {
            Task {
                try? await Task.sleep(for: .seconds(delay))
                restore()
            }
        }
    }

    private func restore() {
        guard let coreDisplay = Self.coreDisplay else {
            return
        }

        for displayID in enabledDisplayIDs
            where !coreDisplay.isHDREnabled(displayID)
        {
            let result = coreDisplay.setHDREnabled(displayID, true)
            if result != 0 {
                AppLog.display.error(
                    "Could not restore HDR for display \(displayID): \(result)"
                )
            }
        }
    }

    private static func onlineDisplayIDs() -> [CGDirectDisplayID]? {
        var displayCount: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &displayCount) == .success else {
            return nil
        }

        var displayIDs = [CGDirectDisplayID](
            repeating: 0,
            count: Int(displayCount)
        )
        guard CGGetOnlineDisplayList(
            displayCount,
            &displayIDs,
            &displayCount
        ) == .success else {
            return nil
        }

        return Array(displayIDs.prefix(Int(displayCount)))
    }
}

private final class CoreDisplayFunctions: @unchecked Sendable {
    typealias IsHDREnabled = @convention(c) (CGDirectDisplayID) -> Bool
    typealias SetHDREnabled = @convention(c) (CGDirectDisplayID, Bool) -> Int32

    let handle: UnsafeMutableRawPointer
    let isHDREnabled: IsHDREnabled
    let setHDREnabled: SetHDREnabled

    private init(
        handle: UnsafeMutableRawPointer,
        isHDREnabled: IsHDREnabled,
        setHDREnabled: SetHDREnabled
    ) {
        self.handle = handle
        self.isHDREnabled = isHDREnabled
        self.setHDREnabled = setHDREnabled
    }

    deinit {
        dlclose(handle)
    }

    static func load() -> CoreDisplayFunctions? {
        let frameworkPath =
            "/System/Library/Frameworks/CoreDisplay.framework/CoreDisplay"
        guard let handle = dlopen(frameworkPath, RTLD_LAZY | RTLD_LOCAL) else {
            return nil
        }
        guard
            let isHDRSymbol = dlsym(
                handle,
                "CoreDisplay_Display_IsHDRModeEnabled"
            ),
            let setHDRSymbol = dlsym(
                handle,
                "CoreDisplay_Display_SetHDRModeEnabled"
            )
        else {
            dlclose(handle)
            return nil
        }

        return CoreDisplayFunctions(
            handle: handle,
            isHDREnabled: unsafeBitCast(
                isHDRSymbol,
                to: IsHDREnabled.self
            ),
            setHDREnabled: unsafeBitCast(
                setHDRSymbol,
                to: SetHDREnabled.self
            )
        )
    }
}

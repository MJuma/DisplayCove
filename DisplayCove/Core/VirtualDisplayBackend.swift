import AppKit

enum VirtualDisplayBackendError: LocalizedError {
    case creationFailed(String)

    var errorDescription: String? {
        switch self {
        case let .creationFailed(message):
            message
        }
    }
}

@MainActor
final class VirtualDisplayHandle {
    fileprivate let display: AnyObject
    let displayID: CGDirectDisplayID

    fileprivate init(display: AnyObject, displayID: CGDirectDisplayID) {
        self.display = display
        self.displayID = displayID
    }
}

@MainActor
final class VirtualDisplayBackend {
    func create(
        configuration: DisplaySessionConfiguration
    ) throws -> VirtualDisplayHandle {
        var error: NSError?
        guard let display = DCVirtualDisplayCreate(
            configuration.name,
            configuration.maxPixelWidth,
            configuration.maxPixelHeight,
            configuration.physicalSize,
            configuration.productID,
            configuration.vendorID,
            configuration.serialNumber,
            configuration.isHiDPI,
            modeDictionaries(configuration.modes),
            &error
        ) else {
            throw VirtualDisplayBackendError.creationFailed(
                error?.localizedDescription ??
                    "macOS could not create the virtual display."
            )
        }

        return VirtualDisplayHandle(
            display: display as AnyObject,
            displayID: DCVirtualDisplayGetDisplayID(display)
        )
    }

    func forceResolution(
        _ resolution: DisplayResolution,
        configuration: DisplaySessionConfiguration,
        on handle: VirtualDisplayHandle
    ) throws {
        try apply(
            modes: [
                DisplayModeConfiguration(
                    width: resolution.width,
                    height: resolution.height,
                    refreshRate: 60
                ),
            ],
            configuration: configuration,
            to: handle
        )
    }

    func restoreAvailableModes(
        preferredResolution: DisplayResolution,
        configuration: DisplaySessionConfiguration,
        on handle: VirtualDisplayHandle
    ) throws {
        let preferredMode = DisplayModeConfiguration(
            width: preferredResolution.width,
            height: preferredResolution.height,
            refreshRate: 60
        )
        let modes = [preferredMode] + configuration.modes.filter {
            $0.width != preferredMode.width ||
                $0.height != preferredMode.height
        }

        try apply(
            modes: modes,
            configuration: configuration,
            to: handle
        )
    }

    private func apply(
        modes: [DisplayModeConfiguration],
        configuration: DisplaySessionConfiguration,
        to handle: VirtualDisplayHandle
    ) throws {
        var error: NSError?
        guard DCVirtualDisplayApplyModes(
            handle.display,
            configuration.isHiDPI,
            modeDictionaries(modes),
            &error
        ) else {
            throw VirtualDisplayBackendError.creationFailed(
                error?.localizedDescription ??
                    "macOS rejected the virtual display settings."
            )
        }
    }

    private func modeDictionaries(
        _ modes: [DisplayModeConfiguration]
    ) -> [[String: NSNumber]] {
        modes.map {
            [
                "width": NSNumber(value: $0.width),
                "height": NSNumber(value: $0.height),
                "refreshRate": NSNumber(value: Double($0.refreshRate)),
            ]
        }
    }
}

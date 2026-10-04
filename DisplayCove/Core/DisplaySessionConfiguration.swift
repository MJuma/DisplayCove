import CoreGraphics

struct DisplayModeConfiguration: Equatable {
    let width: Int
    let height: Int
    let refreshRate: CGFloat
}

struct DisplaySessionConfiguration: Equatable {
    let name: String
    let maxPixelWidth: UInt32
    let maxPixelHeight: UInt32
    let physicalSize: CGSize
    let productID: UInt32
    let vendorID: UInt32
    let serialNumber: UInt32
    let isHiDPI: Bool
    let modes: [DisplayModeConfiguration]

    var defaultResolution: DisplayResolution {
        guard let firstMode = modes.first else {
            return DisplayResolution(
                width: Int(maxPixelWidth),
                height: Int(maxPixelHeight)
            )
        }

        return DisplayResolution(
            width: firstMode.width,
            height: firstMode.height
        )
    }

    static func standard(serialNumber: UInt32 = 1) -> DisplaySessionConfiguration {
        highResolution(serialNumber: serialNumber)
    }

    static func highResolution(serialNumber: UInt32 = 1) -> DisplaySessionConfiguration {
        let refreshRate: CGFloat = 60
        let name = serialNumber == 1
            ? "DisplayCove"
            : "DisplayCove \(serialNumber)"

        return DisplaySessionConfiguration(
            name: name,
            maxPixelWidth: 5120,
            maxPixelHeight: 2160,
            physicalSize: CGSize(width: 1600, height: 1000),
            productID: 0x0001,
            vendorID: 0x444356,
            serialNumber: serialNumber,
            isHiDPI: true,
            modes: [
                // 32:9
                DisplayModeConfiguration(width: 5120, height: 1440, refreshRate: refreshRate),
                // 21:9 (239:100, 12:5)
                DisplayModeConfiguration(width: 5120, height: 2160, refreshRate: refreshRate),
                DisplayModeConfiguration(width: 3840, height: 1600, refreshRate: refreshRate),
                DisplayModeConfiguration(width: 3440, height: 1440, refreshRate: refreshRate),
                // 16:9
                DisplayModeConfiguration(width: 3840, height: 2160, refreshRate: refreshRate),
                DisplayModeConfiguration(width: 2560, height: 1440, refreshRate: refreshRate),
                DisplayModeConfiguration(width: 1920, height: 1080, refreshRate: refreshRate),
                DisplayModeConfiguration(width: 1600, height: 900, refreshRate: refreshRate),
                DisplayModeConfiguration(width: 1366, height: 768, refreshRate: refreshRate),
                DisplayModeConfiguration(width: 1280, height: 720, refreshRate: refreshRate),
                // 16:10
                DisplayModeConfiguration(width: 2560, height: 1600, refreshRate: refreshRate),
                DisplayModeConfiguration(width: 1920, height: 1200, refreshRate: refreshRate),
                DisplayModeConfiguration(width: 1680, height: 1050, refreshRate: refreshRate),
                DisplayModeConfiguration(width: 1440, height: 900, refreshRate: refreshRate),
                DisplayModeConfiguration(width: 1280, height: 800, refreshRate: refreshRate),
            ]
        )
    }
}

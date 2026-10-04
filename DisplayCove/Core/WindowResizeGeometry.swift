import CoreGraphics

enum WindowResizeGeometry {
    static func snappedContentSize(
        proposedContentSize: CGSize,
        nativeResolution: CGSize,
        snappingThreshold: CGFloat
    ) -> CGSize? {
        guard
            proposedContentSize.width.isFinite,
            proposedContentSize.height.isFinite,
            nativeResolution.width.isFinite,
            nativeResolution.height.isFinite,
            snappingThreshold.isFinite,
            proposedContentSize.width > 0,
            proposedContentSize.height > 0,
            nativeResolution.width > 0,
            nativeResolution.height > 0,
            snappingThreshold >= 0
        else {
            return nil
        }

        let isNearNativeWidth =
            abs(proposedContentSize.width - nativeResolution.width) < snappingThreshold
        let isNearNativeHeight =
            abs(proposedContentSize.height - nativeResolution.height) < snappingThreshold

        guard isNearNativeWidth || isNearNativeHeight else {
            return nil
        }

        return nativeResolution
    }
}

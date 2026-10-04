import CoreGraphics

enum DisplayGeometry {
    static func displayPoint(
        from viewPoint: CGPoint,
        viewSize: CGSize,
        displayResolution: CGSize
    ) -> CGPoint? {
        guard
            viewPoint.x.isFinite,
            viewPoint.y.isFinite,
            viewSize.width.isFinite,
            viewSize.height.isFinite,
            displayResolution.width.isFinite,
            displayResolution.height.isFinite,
            viewSize.width > 0,
            viewSize.height > 0,
            displayResolution.width > 0,
            displayResolution.height > 0
        else {
            return nil
        }

        return CGPoint(
            x: viewPoint.x / viewSize.width * displayResolution.width,
            y: (viewSize.height - viewPoint.y) / viewSize.height * displayResolution.height
        )
    }
}

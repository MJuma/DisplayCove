import Cocoa

final class RecordingIndicatorView: NSVisualEffectView {
    private let label = NSTextField(labelWithString: "● REC 00:00")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        material = .hudWindow
        blendingMode = .withinWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = 6

        label.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        label.textColor = .systemRed
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 5),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -5),
        ])
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(duration: TimeInterval) {
        guard duration.isFinite else {
            return
        }

        let totalSeconds = max(0, Int(duration))
        label.stringValue = String(
            format: "● REC %02d:%02d",
            totalSeconds / 60,
            totalSeconds % 60
        )
    }
}

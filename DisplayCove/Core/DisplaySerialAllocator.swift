final class DisplaySerialAllocator {
    private let availableSerials: ClosedRange<UInt32>
    private var claimedSerials: Set<UInt32> = []

    init(availableSerials: ClosedRange<UInt32> = 1 ... UInt32.max) {
        self.availableSerials = availableSerials
    }

    func claim() -> UInt32? {
        var candidate = availableSerials.lowerBound

        while claimedSerials.contains(candidate) {
            guard candidate < availableSerials.upperBound else {
                return nil
            }

            candidate += 1
        }

        claimedSerials.insert(candidate)
        return candidate
    }

    func release(_ serialNumber: UInt32) {
        claimedSerials.remove(serialNumber)
    }
}

import Foundation

enum ApplicationInstancePolicy {
    static func shouldTerminate(
        currentProcessID: Int32,
        matchingProcessIDs: [Int32]
    ) -> Bool {
        let validProcessIDs = matchingProcessIDs.filter { $0 > 0 }
        guard let ownerProcessID = validProcessIDs.min() else {
            return false
        }

        return ownerProcessID != currentProcessID
    }
}

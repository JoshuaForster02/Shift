import Foundation

// Original implementation of the MIT-licensed OpenBikeControl specification.
// Specification: https://github.com/OpenBikeControl/openbikecontrol-protocol
enum ShiftAction: UInt8 {
    case up = 0x01, down = 0x02
    var title: String { self == .up ? "Hochschalten" : "Runterschalten" }
    var opposite: ShiftAction { self == .up ? .down : .up }
    func packet(pressed: Bool) -> Data { Data([0x01, rawValue, pressed ? 1 : 0]) }
}

struct DirectionLatch {
    private(set) var held: ShiftAction?
    mutating func update(x: Float, inverted: Bool) -> [(ShiftAction, Bool)] {
        guard x.isFinite else { return [] }
        let direction: ShiftAction? = x > 0.5 ? .up : (x < -0.5 ? .down : nil)
        let next = inverted ? direction?.opposite : direction
        guard next != held else { return [] }
        var changes: [(ShiftAction, Bool)] = []
        if let held { changes.append((held, false)) }
        held = next
        if let next { changes.append((next, true)) }
        return changes
    }
}

struct PeerInfo: Equatable {
    let name: String
    let version: String
    let buttons: Set<UInt8>
    func supports(_ action: ShiftAction) -> Bool { buttons.isEmpty || buttons.contains(action.rawValue) }
}

// A TCP read is not a complete message: retain partial app-info frames and
// consume concatenated frames. Bound memory for malformed/untrusted clients.
struct PeerParser {
    private var bytes: [UInt8] = []
    mutating func feed(_ data: Data) throws -> [PeerInfo] {
        guard bytes.count + data.count <= 4096 else { throw ParseError.tooLarge }
        bytes += data
        var peers: [PeerInfo] = []
        while !bytes.isEmpty {
            switch bytes[0] {
            case 0x03:
                guard bytes.count >= 4 else { return peers }
                bytes.removeFirst(4) // Optional haptic message; no controller rumble required.
            case 0x04:
                guard bytes.count >= 3 else { return peers }
                guard bytes[1] == 1, bytes[2] <= 32 else { throw ParseError.invalid }
                let nameEnd = 3 + Int(bytes[2])
                guard bytes.count > nameEnd else { return peers }
                let versionCount = Int(bytes[nameEnd])
                guard versionCount <= 32 else { throw ParseError.invalid }
                let versionEnd = nameEnd + 1 + versionCount
                guard bytes.count > versionEnd else { return peers }
                let end = versionEnd + 1 + Int(bytes[versionEnd])
                guard bytes.count >= end else { return peers }
                guard let name = String(bytes: bytes[3..<nameEnd], encoding: .utf8),
                      let version = String(bytes: bytes[(nameEnd + 1)..<versionEnd], encoding: .utf8),
                      !name.isEmpty else { throw ParseError.invalid }
                peers.append(PeerInfo(name: name, version: version, buttons: Set(bytes[(versionEnd + 1)..<end])))
                bytes.removeFirst(end)
            default:
                throw ParseError.invalid
            }
        }
        return peers
    }
    enum ParseError: Error { case invalid, tooLarge }
}

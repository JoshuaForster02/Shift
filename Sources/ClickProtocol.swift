import Foundation

// Click V2 facts from thomaschampagne/zwiftboard (MIT), revision
// ee4b1f2156d316398f71aeb09b67282901456b8e. Attribution in THIRD_PARTY_NOTICES.md.
struct ClickButtons: Equatable {
    let plus: Bool
    let minus: Bool
    var direction: Float { plus == minus ? 0 : (plus ? 1 : -1) }
    static let released = ClickButtons(plus: false, minus: false)
    static func decode(_ data: Data) -> ClickButtons? {
        let bytes = Array(data)
        guard bytes.count > 1, bytes.count <= 512, bytes[0] == 0x23 else { return nil }
        var i = 1
        func read() -> UInt32? {
            var value: UInt32 = 0
            for n in 0..<5 {
                guard i < bytes.count else { return nil }
                let b = bytes[i]; i += 1
                if n == 4 && b > 15 { return nil }
                value |= UInt32(b & 127) << (n * 7)
                if b & 128 == 0 { return value }
            }
            return nil
        }
        var bitmap: UInt32?
        while i < bytes.count {
            guard let tag = read(), tag >> 3 > 0 else { return nil }
            switch tag & 7 {
            case 0:
                guard let value = read() else { return nil }
                if tag >> 3 == 1 {
                    guard bitmap == nil else { return nil }
                    bitmap = value
                }
            case 1: i += 8
            case 2:
                guard let length = read(), length <= 512 else { return nil }
                i += Int(length)
            case 5: i += 4
            default: return nil
            }
            guard i <= bytes.count else { return nil }
        }
        guard let bitmap else { return nil }
        return ClickButtons(plus: bitmap & 0x1000 == 0, minus: bitmap & 0x100 == 0)
    }
}

enum ClickProtocol {
    static let rideOn = Data("RideOn".utf8)
    static let activation = [rideOn + Data([2, 3]), Data([0, 8, 0]), Data([0, 8, 16])]
    static let acknowledgement = Data([0xff, 4, 0])
    static func needsActivation(_ data: Data) -> Bool { data.count >= 2 && data.prefix(2) == Data([0xff, 3]) }
}

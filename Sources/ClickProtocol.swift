import Foundation

// Click V2 facts from thomaschampagne/zwiftboard (MIT), revision
// ee4b1f2156d316398f71aeb09b67282901456b8e. Attribution in THIRD_PARTY_NOTICES.md.
struct ClickButtons: Equatable {
    let plus: Bool
    let minus: Bool
    var direction: Float { plus == minus ? 0 : (plus ? 1 : -1) }
    static let released = ClickButtons(plus: false, minus: false)
    static func decode(_ data: Data, version: Int = 2) -> ClickButtons? {
        let bytes = Array(data)
        guard bytes.count > 1, bytes.count <= 512, bytes[0] == (version == 1 ? 0x37 : 0x23) else { return nil }
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
        var minus: UInt32?
        while i < bytes.count {
            guard let tag = read(), tag >> 3 > 0 else { return nil }
            if (tag >> 3 == 1 || (version == 1 && tag >> 3 == 2)) && tag & 7 != 0 { return nil }
            switch tag & 7 {
            case 0:
                guard let value = read() else { return nil }
                if tag >> 3 == 1 {
                    guard bitmap == nil else { return nil }
                    bitmap = value
                }
                if version == 1 && tag >> 3 == 2 {
                    guard minus == nil else { return nil }; minus = value
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
        if version == 1 {
            guard bitmap != nil || minus != nil, (bitmap ?? 0) <= 1, (minus ?? 0) <= 1 else { return nil }
            return ClickButtons(plus: (bitmap ?? 0) == 0, minus: (minus ?? 0) == 0)
        }
        guard let bitmap else { return nil }
        if version == 3 { return ClickButtons(plus: bitmap & 0x200 == 0 || bitmap & 0x2000 == 0,
                                              minus: bitmap & 0x400 == 0 || bitmap & 0x4000 == 0) }
        return ClickButtons(plus: bitmap & 0x1000 == 0, minus: bitmap & 0x100 == 0)
    }
}

enum ClickProtocol {
    static let rideOn = Data("RideOn".utf8)
    static let activation = [rideOn + Data([2, 3]), Data([0, 8, 0]), Data([0, 8, 16])]
    static let acknowledgement = Data([0xff, 4, 0])
    static func needsActivation(_ data: Data) -> Bool { data.count >= 2 && data.prefix(2) == Data([0xff, 3]) }
}

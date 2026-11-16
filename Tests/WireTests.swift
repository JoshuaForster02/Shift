import Foundation

@main struct WireTests {
    static func main() throws {
        var count = 0
        func check(_ value: @autoclosure () -> Bool, _ name: String) {
            precondition(value(), name)
            count += 1
        }
        check(ShiftAction.up.packet(pressed: true) == Data([1, 1, 1]), "Up packet")
        check(ShiftAction.down.packet(pressed: false) == Data([1, 2, 0]), "Release packet")
        var latch = DirectionLatch()
        check(latch.update(x: 1, inverted: false).count == 1 && latch.held == .up, "Right shifts up")
        check(latch.update(x: 1, inverted: false).isEmpty, "Held direction is not duplicated")
        check(latch.update(x: 0.8, inverted: false).isEmpty, "Analog jitter is ignored")
        let switched = latch.update(x: -1, inverted: false)
        check(switched.count == 2 && switched[0].0 == .up && !switched[0].1 && switched[1].0 == .down && switched[1].1,
              "Direction switch releases previous action first")
        check(latch.update(x: 0, inverted: false).count == 1 && latch.held == nil, "Neutral releases")
        check(latch.update(x: .nan, inverted: false).isEmpty, "NaN ignored")
        check(latch.update(x: .infinity, inverted: false).isEmpty, "Infinity ignored")
        check(latch.update(x: 1, inverted: true).first?.0 == .down, "Reverse layout")
        let name = Array("mywhoosh".utf8)
        let version = Array("6.3.0".utf8)
        let frame = Data([4, 1, UInt8(name.count)] + name + [UInt8(version.count)] + version + [2, 1, 2])
        var parser = PeerParser()
        var info: [PeerInfo] = []
        for byte in frame { info += try parser.feed(Data([byte])) }
        check(info.count == 1 && info[0].name == "mywhoosh" && info[0].version == "6.3.0", "Fragmented TCP frame")
        check(info[0].supports(.up) && info[0].supports(.down), "Capability list")
        check(!PeerInfo(name: "test", version: "1", buttons: [1]).supports(.down), "Unsupported action")
        check(PeerInfo(name: "test", version: "1", buttons: []).supports(.down), "Empty capabilities means all")
        var combined = PeerParser()
        let combinedInfo = try combined.feed(Data([3, 1, 0, 0]) + frame + frame)
        check(combinedInfo.count == 2, "Coalesced frames with optional haptics")
        for bad in [Data([4, 2, 0]), Data([4, 1, 33]), Data([0xFF]), Data(repeating: 1, count: 4097)] {
            do { var parser = PeerParser(); _ = try parser.feed(bad); preconditionFailure("Malformed input accepted") }
            catch { count += 1 }
        }
        print("\(count) protocol and input tests passed")
    }
}

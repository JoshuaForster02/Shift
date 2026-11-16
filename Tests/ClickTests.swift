import Foundation
@main struct ClickTests {
    static func main() {
        var count = 0
        func check(_ value: @autoclosure () -> Bool, _ name: String) {
            precondition(value(), name); count += 1
        }
        func frame(_ mask: UInt32) -> Data {
            var b: [UInt8] = [0x23, 8], n = mask
            repeat { let v = UInt8(n & 127); n >>= 7; b.append(v | (n == 0 ? 0 : 128)) } while n != 0
            return Data(b)
        }
        check(ClickButtons.decode(frame(.max)) == .released, "All bits one releases")
        check(ClickButtons.decode(frame(0xffffefff)) == ClickButtons(plus: true, minus: false), "Plus is bit 12")
        check(ClickButtons.decode(frame(0xfffffeff)) == ClickButtons(plus: false, minus: true), "Minus is bit 8")
        check(ClickButtons.decode(frame(0xfffffdff)) == .released, "Ride shift bit is not a Click shift")
        check(ClickButtons(plus: true, minus: true).direction == 0, "Both buttons are neutral")
        for b: [UInt8] in [[0x23], [0x23,8,128], [0x23,8,255,255,255,255,31], [0x23,0], [0x23,8,1,18,10,0], [0x23,8,1,8,2], [0xff,3], [0x37,8,0]] {
            check(ClickButtons.decode(Data(b)) == nil, "Malformed/other packet ignored")
        }
        var latch = DirectionLatch()
        let plus = ClickButtons.decode(frame(0xffffefff))!
        let first = latch.update(x: plus.direction, inverted: false)
        check(first.count == 1 && first[0].0.packet(pressed: first[0].1) == Data([1,1,1]), "Click plus routes to MyWhoosh up packet")
        check(latch.update(x: plus.direction, inverted: false).isEmpty, "Second mirrored pod does not shift twice")
        let release = latch.update(x: 0, inverted: false)
        check(release.count == 1 && release[0].0.packet(pressed: release[0].1) == Data([1,1,0]), "Click release routes to MyWhoosh")
        check(latch.update(x: plus.direction, inverted: true).first?.0 == .down, "Inversion applies to Click")
        check(ClickProtocol.activation == [Data([82,105,100,101,79,110,2,3]), Data([0,8,0]), Data([0,8,16])], "V2 activation sequence")
        check(ClickProtocol.needsActivation(Data([255,3,1])), "Server challenge detected")
        check(!ClickProtocol.needsActivation(Data([255])), "Truncated challenge ignored")
        print("\(count) Click V2 checks passed")
    }
}

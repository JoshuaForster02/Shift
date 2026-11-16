import Foundation
@main struct SetupTests {
    static func main() throws {
        var n = 0
        func check(_ condition: @autoclosure () -> Bool, _ label: String) { precondition(condition(), label); n += 1 }
        let a = UUID(), b = UUID(), c = UUID()
        check(PodSide.fromManufacturer(Data([0x4a,0x09,0x0a])) == .right, "Right V2 advertisement")
        check(PodSide.fromManufacturer(Data([0x4a,0x09,0x0b])) == .left, "Left V2 advertisement")
        check(PodSide.fromManufacturer(Data([0x4a,0x08,0x0b])) == .unknown, "Other vendor is not a Zwift pod")
        check(PodSide.fromManufacturer(Data([0x4a,0x09])) == .unknown, "Truncated advertisement ignored")
        check(PodSide.fromManufacturer(Data([0x4a,0x09,9])) == .unknown, "V1 has no V2 side")
        check(PairSelection.uniquePair([.init(id: a, side: .left), .init(id: a, side: .right)]) == nil, "One identifier cannot be both pods")
        check(PairSelection.uniquePair([.init(id: a, side: .left)]) == nil, "One pod is not a pair")
        check(PairSelection.uniquePair([.init(id: a, side: .left), .init(id: b, side: .right)]) == [a,b], "Unique left and right")
        check(PairSelection.uniquePair([.init(id: a, side: .left), .init(id: c, side: .left), .init(id: b, side: .right)]) == nil, "Ambiguous neighbour is not auto-selected")
        check(PairSelection.uniquePair([.init(id: a, side: .unknown), .init(id: b, side: .right)]) == nil, "Unknown side requires manual selection")
        var buttons = ButtonCheck()
        buttons.observe(.released); check(!buttons.complete, "A release is not a button test")
        buttons.observe(.init(plus: true, minus: true)); check(!buttons.plus && !buttons.minus, "Simultaneous buttons do not pass separate tests")
        buttons.release(); buttons.observe(.init(plus: true, minus: false)); check(buttons.plus && !buttons.minus, "Plus tested independently")
        buttons.observe(.init(plus: true, minus: false)); check(!buttons.complete, "Mirrored press is not a second test")
        buttons.observe(.released); buttons.observe(.init(plus: false, minus: true)); check(buttons.complete, "Both physical actions observed")
        buttons.reset(); check(!buttons.complete && !buttons.plus, "Test reset")
        var readiness = SetupReadiness(pairConnected: false, appConnected: true, buttonsTested: true)
        check(!readiness.permits(.controller) && !readiness.permits(.test), "App and buttons cannot hide a missing pod")
        readiness.pairConnected = true; readiness.appConnected = false
        check(readiness.permits(.controller) && !readiness.permits(.app), "MyWhoosh must really connect")
        readiness.appConnected = true; readiness.buttonsTested = false
        check(readiness.permits(.app) && !readiness.permits(.test), "Cannot finish without both button tests")
        readiness.buttonsTested = true; check(readiness.permits(.test), "All setup evidence required")
        let profile = ShiftProfile(name: "MyWhoosh · Click V2", source: .clickV2, gamepad: .dpad, reversed: false, holdToRepeat: true, inputUp: .up, inputDown: .down, outputUp: .up, outputDown: .down)
        let data = try JSONEncoder().encode(profile), decoded = try JSONDecoder().decode(ShiftProfile.self, from: data).validated()
        check(decoded == profile, "Shareable profile roundtrip")
        let text = String(decoding: data, as: UTF8.self)
        check(!text.contains("outputArmed") && !text.contains("deviceID"), "No permission or device identity in profile")
        var bad = profile; bad.schema = 99
        do { _ = try bad.validated(); preconditionFailure("Schema accepted") } catch { n += 1 }
        bad = profile; bad.inputDown = bad.inputUp
        do { _ = try bad.validated(); preconditionFailure("Duplicate key accepted") } catch { n += 1 }
        bad = profile; bad.outputUp.modifiers = UInt64.max
        do { _ = try bad.validated(); preconditionFailure("Invalid flags accepted") } catch { n += 1 }
        print("\(n) setup, dual-pod and sharing checks passed")
    }
}

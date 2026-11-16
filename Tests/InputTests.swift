import Foundation
@main struct InputTests {
    static func main() throws {
        var count = 0
        func check(_ value: @autoclosure () -> Bool, _ name: String) { precondition(value(), name); count += 1 }
        let up = KeyBinding(code: 124, modifiers: 1 << 19), down = KeyBinding(code: 123)
        var keys = RemoteKeys()
        check(keys.update(code: 124, modifiers: 0, down: true, upBinding: up, downBinding: down) == nil, "Wrong modifiers ignored")
        check(keys.update(code: 5, modifiers: 0, down: true, upBinding: up, downBinding: down) == nil, "Unmapped typing ignored")
        check(keys.update(code: 124, modifiers: 1 << 19, down: true, upBinding: up, downBinding: down) == 1, "Mapped key shifts up")
        check(keys.update(code: 124, modifiers: 0, down: false, upBinding: up, downBinding: down) == 0, "Release works after modifier release")
        check(keys.update(code: 123, modifiers: 0, down: true, upBinding: up, downBinding: down) == -1, "Mapped minus")
        check(keys.update(code: 124, modifiers: 1 << 19, down: true, upBinding: up, downBinding: down) == 0, "Both pressed cancel")
        check(keys.update(code: 123, modifiers: 0, down: false, upBinding: up, downBinding: down) == 1, "One remaining held key")
        keys.reset()
        check(keys.update(code: 124, modifiers: 0, down: false, upBinding: up, downBinding: down) == nil, "Reset clears held keys")
        let data = try JSONEncoder().encode(up)
        let decoded = try JSONDecoder().decode(KeyBinding.self, from: data)
        check(decoded == up, "Binding roundtrip")
        check(up.title == "⌥→", "Readable binding")
        check(ControllerSource.clickV1.clickVersion == 1 && ControllerSource.clickV2.clickVersion == 2, "BLE versions distinct")
        check(ControllerSource.keyboard.clickVersion == nil && GamepadBinding.allCases.count == 6, "HID and gamepad presets")
        var latch = DirectionLatch()
        check(latch.update(x: 1, inverted: false).first?.0.packet(pressed: true) == Data([1,1,1]), "HID can route through same network path")
        check(latch.update(x: 1, inverted: false).isEmpty, "Duplicate input does not repeat")
        print("\(count) controller mapping and key tests passed")
    }
}

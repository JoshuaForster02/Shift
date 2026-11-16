import Foundation

enum ControllerSource: String, CaseIterable, Identifiable {
    case gamepad, clickV1, clickV2, keyboard
    var id: String { rawValue }
    var title: String {
        switch self { case .gamepad: return "Gamepad"; case .clickV1: return "Click V1"; case .clickV2: return "Click V2"; case .keyboard: return "Tastatur" }
    }
    var clickVersion: Int? { self == .clickV1 ? 1 : (self == .clickV2 ? 2 : nil) }
}
enum GamepadBinding: String, CaseIterable, Identifiable {
    case dpad, shoulders, triggers, face, leftStick, rightStick
    var id: String { rawValue }
    var title: String {
        switch self {
        case .dpad: return "Steuerkreuz links / rechts"
        case .shoulders: return "Schultertasten LB / RB"
        case .triggers: return "Trigger LT / RT"
        case .face: return "Aktionstasten X / B"
        case .leftStick: return "Linker Stick"
        case .rightStick: return "Rechter Stick"
        }
    }
}
enum OutputMode: String, CaseIterable, Identifiable {
    case myWhoosh, keyboard
    var id: String { rawValue }
    var title: String { self == .myWhoosh ? "MyWhoosh · Netzwerk" : "Tastatur · ausgewählte App" }
}
struct KeyBinding: Codable, Equatable {
    var code: UInt16
    var modifiers: UInt64 = 0
    var title: String {
        let name = [UInt16(123): "←", 124: "→", 125: "↓", 126: "↑", 24: "+", 27: "−", 34: "I", 40: "K", 49: "Leertaste"][code] ?? "Taste \(code)"
        let prefix = (modifiers & (1 << 20) != 0 ? "⌘" : "") + (modifiers & (1 << 19) != 0 ? "⌥" : "") + (modifiers & (1 << 18) != 0 ? "⌃" : "") + (modifiers & (1 << 17) != 0 ? "⇧" : "")
        return prefix + name
    }
    static func load(_ key: String, fallback: KeyBinding) -> KeyBinding {
        guard let data = UserDefaults.standard.data(forKey: key), let value = try? JSONDecoder().decode(KeyBinding.self, from: data) else { return fallback }
        return value
    }
    func save(_ key: String) { if let data = try? JSONEncoder().encode(self) { UserDefaults.standard.set(data, forKey: key) } }
    static let up = KeyBinding(code: 124)
    static let down = KeyBinding(code: 123)
}
// Track key identity on key-up even if a modifier was released first.
struct RemoteKeys {
    private var held: [UInt16: Bool] = [:]
    mutating func update(code: UInt16, modifiers: UInt64, down: Bool, upBinding: KeyBinding, downBinding: KeyBinding) -> Float? {
        if down {
            if code == upBinding.code && modifiers == upBinding.modifiers { held[code] = true }
            else if code == downBinding.code && modifiers == downBinding.modifiers { held[code] = false }
            else { return nil }
        } else {
            guard held.removeValue(forKey: code) != nil else { return nil }
        }
        let plus = held.values.contains(true), minus = held.values.contains(false)
        return plus == minus ? 0 : (plus ? 1 : -1)
    }
    mutating func reset() { held.removeAll() }
}

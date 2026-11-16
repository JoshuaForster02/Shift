import Foundation

enum SetupStep: Int, CaseIterable {
    case controller, app, test
    var title: String {
        switch self { case .controller: return "Controller"; case .app: return "MyWhoosh"; case .test: return "Tastentest" }
    }
}
struct SetupReadiness {
    var pairConnected: Bool
    var appConnected: Bool
    var buttonsTested: Bool
    func permits(_ step: SetupStep) -> Bool {
        switch step {
        case .controller: return pairConnected
        case .app: return pairConnected && appConnected
        case .test: return pairConnected && appConnected && buttonsTested
        }
    }
}
enum PodSide: String, Codable {
    case left, right, unknown
    static func fromManufacturer(_ data: Data) -> PodSide {
        let bytes = Array(data)
        guard bytes.count >= 3, bytes[0] == 0x4a, bytes[1] == 0x09 else { return .unknown }
        if bytes[2] == 0x0a { return .right }
        if bytes[2] == 0x0b || bytes[2] == 8 { return .left }
        return .unknown
    }
}
struct PodCandidate: Equatable {
    let id: UUID
    let side: PodSide
}
enum PairSelection {
    // Never silently select among several neighbouring pairs.
    static func uniquePair(_ candidates: [PodCandidate]) -> [UUID]? {
        let left = candidates.filter { $0.side == .left }, right = candidates.filter { $0.side == .right }
        guard left.count == 1, right.count == 1, left[0].id != right[0].id else { return nil }
        return [left[0].id, right[0].id]
    }
}
struct ButtonCheck {
    private(set) var plus = false
    private(set) var minus = false
    private var previous = ClickButtons.released
    mutating func observe(_ buttons: ClickButtons) {
        if buttons.plus && !buttons.minus && !previous.plus { plus = true }
        if buttons.minus && !buttons.plus && !previous.minus { minus = true }
        previous = buttons
    }
    mutating func release() { previous = .released }
    mutating func reset() { self = ButtonCheck() }
    var complete: Bool { plus && minus }
}
struct ShiftProfile: Codable, Equatable {
    var schema = 1
    var name: String
    var source: ControllerSource
    var gamepad: GamepadBinding
    var reversed: Bool
    var holdToRepeat: Bool
    var inputUp: KeyBinding
    var inputDown: KeyBinding
    var outputUp: KeyBinding
    var outputDown: KeyBinding
    // Output arming, permissions and device identifiers are never transferred.
    func validated() throws -> ShiftProfile {
        guard schema == 1, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              name.count <= 60, inputUp.code != inputDown.code,
              [inputUp, inputDown, outputUp, outputDown].allSatisfy({ $0.code <= 127 && $0.modifiers & ~UInt64(0x1e0000) == 0 }) else { throw ProfileError.invalid }
        return self
    }
    enum ProfileError: Error { case invalid }
}

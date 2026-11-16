import AppKit
import ApplicationServices

final class KeyboardBridge {
    static let marker: Int64 = 0x53484654
    var onKey: ((UInt16, UInt64, Bool) -> Void)?
    var onLearn: ((KeyBinding) -> Void)?
    private var global: Any?
    private var local: Any?
    private var learning = false
    private var pressed: [UInt16: KeyBinding] = [:]
    private var outputPID: pid_t?
    private var outputBundle: String?
    var trusted: Bool { AXIsProcessTrusted() }
    func askPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }
    func start() {
        stopMonitoring()
        global = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in self?.handle(event, local: false) }
        local = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            guard let self else { return event }
            let consumed = self.learning && event.type == .keyDown
            self.handle(event, local: true)
            return consumed ? nil : event
        }
    }
    func learn() { learning = true }
    func cancelLearn() { learning = false }
    private func handle(_ event: NSEvent, local: Bool) {
        guard event.cgEvent?.getIntegerValueField(.eventSourceUserData) != Self.marker, !event.isARepeat else { return }
        let flags = UInt64(event.modifierFlags.intersection([.command, .option, .control, .shift]).rawValue)
        if learning && event.type == .keyDown {
            learning = false; onLearn?(KeyBinding(code: event.keyCode, modifiers: flags)); return
        }
        // Ordinary typing in Shift never controls another app. Global monitoring
        // only forwards the two explicitly configured keys; no text is retained.
        if !local { onKey?(event.keyCode, flags, event.type == .keyDown) }
    }
    func arm(_ pid: pid_t?) {
        releaseAll(); outputPID = pid
        outputBundle = pid.flatMap { NSRunningApplication(processIdentifier: $0)?.bundleIdentifier }
    }
    @discardableResult func send(_ binding: KeyBinding, down: Bool) -> Bool {
        guard trusted, let pid = outputPID, let app = NSRunningApplication(processIdentifier: pid), !app.isTerminated,
              let outputBundle, app.bundleIdentifier == outputBundle,
              let event = CGEvent(keyboardEventSource: nil, virtualKey: binding.code, keyDown: down) else { return false }
        event.flags = CGEventFlags(rawValue: binding.modifiers)
        event.setIntegerValueField(.eventSourceUserData, value: Self.marker)
        event.postToPid(pid)
        if down { pressed[binding.code] = binding } else { pressed.removeValue(forKey: binding.code) }
        return true
    }
    func releaseAll() {
        for binding in Array(pressed.values) { _ = send(binding, down: false) }
        pressed.removeAll()
    }
    func stopMonitoring() {
        if let global { NSEvent.removeMonitor(global) }
        if let local { NSEvent.removeMonitor(local) }
        global = nil; local = nil
    }
    func stop() { stopMonitoring(); releaseAll(); learning = false; outputPID = nil }
    deinit { stop() }
}

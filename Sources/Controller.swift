import AppKit
import Combine
import GameController

final class ShiftModel: ObservableObject {
    @Published var controllerName: String?
    @Published var connectionText = "Verbindung wird vorbereitet …"
    @Published var appName: String?
    @Published var networkReady = false
    @Published var connected = false
    @Published var lastInput = "Noch keine Eingabe"
    @Published var lastDirection: ShiftAction?
    @Published var commands = 0
    @Published var reversed = UserDefaults.standard.bool(forKey: "reversed") {
        didSet { release(); UserDefaults.standard.set(reversed, forKey: "reversed") }
    }
    @Published var holdToRepeat = UserDefaults.standard.object(forKey: "holdToRepeat") as? Bool ?? true {
        didSet { release(); UserDefaults.standard.set(holdToRepeat, forKey: "holdToRepeat") }
    }
    private let bridge = DeviceBridge()
    private var controller: GCController?
    private var latch = DirectionLatch()
    private var observers: [NSObjectProtocol] = []
    private var repeatTimer: Timer?
    private var started = false
    private var inputGeneration = 0

    var ready: Bool { controllerName != nil && connected }
    var headline: String { ready ? "Bereit zum Fahren" : (controllerName == nil ? "Controller verbinden" : "MyWhoosh verbinden") }
    var subtitle: String {
        if ready { return reversed ? "Steuerkreuz links schaltet hoch. Rechts schaltet runter." : "Steuerkreuz rechts schaltet hoch. Links schaltet runter." }
        if controllerName == nil { return "Shanwan oder einen anderen Gamepad-Controller per Bluetooth mit dem Mac verbinden." }
        return networkReady ? "In MyWhoosh bei den Controllern „Shift“ auswählen." : connectionText
    }

    func start() {
        guard !started else { return }
        started = true
        GCController.shouldMonitorBackgroundEvents = true
        bridge.onChange = { [weak self] in
            guard let self else { return }
            self.connectionText = self.bridge.message
            self.networkReady = self.bridge.listening
            self.connected = self.bridge.connected && self.bridge.canShift
            self.appName = self.bridge.connectedName
            if !self.connected { self.release() }
        }
        bridge.onDelivery = { [weak self] action in
            self?.commands += 1
            self?.lastInput = action.title + " gesendet"
        }
        for name in [Notification.Name.GCControllerDidConnect, Notification.Name.GCControllerDidDisconnect] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.refreshController()
            })
        }
        refreshController()
        bridge.start()
    }

    private func refreshController() {
        let next = GCController.controllers().first { $0.extendedGamepad != nil }
        if controller === next { return }
        release()
        controller?.extendedGamepad?.dpad.valueChangedHandler = nil
        controller = next
        controllerName = next?.vendorName ?? (next == nil ? nil : "Gamepad")
        next?.handlerQueue = .main
        next?.extendedGamepad?.dpad.valueChangedHandler = { [weak self] _, x, _ in self?.input(x: x) }
    }

    private func input(x: Float) {
        let changes = latch.update(x: x, inverted: reversed)
        guard !changes.isEmpty else { return }
        inputGeneration += 1
        repeatTimer?.invalidate()
        repeatTimer = nil
        for (action, pressed) in changes {
            bridge.shift(action, pressed: pressed)
            if pressed {
                lastDirection = action
                if !connected { lastInput = action.title + " erkannt · MyWhoosh noch nicht verbunden" }
            }
        }
        if let action = latch.held, holdToRepeat, connected {
            repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
                guard let self, self.latch.held == action, self.connected else { return }
                self.repeatShift(action)
                self.repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
                    guard let self, self.latch.held == action, self.connected else { self?.repeatTimer?.invalidate(); return }
                    self.repeatShift(action)
                }
            }
        }
    }

    func pulse(_ action: ShiftAction) {
        guard connected else { lastInput = "Zuerst MyWhoosh verbinden"; return }
        bridge.shift(action, pressed: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in self?.bridge.shift(action, pressed: false) }
        lastDirection = action
    }

    private func repeatShift(_ action: ShiftAction) {
        let generation = inputGeneration
        bridge.shift(action, pressed: false)
        // Keep release and press as distinct transitions on the TCP stream.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) { [weak self] in
            guard let self, generation == self.inputGeneration, self.connected, self.latch.held == action else { return }
            self.bridge.shift(action, pressed: true)
        }
    }

    private func release() {
        inputGeneration += 1
        repeatTimer?.invalidate()
        repeatTimer = nil
        if let held = latch.held { bridge.shift(held, pressed: false) }
        latch = DirectionLatch()
    }
    func reconnect() { release(); bridge.start(); refreshController() }
    func stop() {
        release()
        controller?.extendedGamepad?.dpad.valueChangedHandler = nil
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        bridge.stop()
        started = false
    }
    func openMyWhoosh() {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.whoosh.whooshgame") {
            NSWorkspace.shared.openApplication(at: url, configuration: .init())
        } else { NSWorkspace.shared.open(URL(string: "https://www.mywhoosh.com/get-mywhoosh/")!) }
    }
    func openBluetooth() { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.BluetoothSettings")!) }
}

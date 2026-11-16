import AppKit
import Combine
import GameController

struct TrainingTarget: Identifiable { let id: String; let name: String }
enum LearnTarget { case inputUp, inputDown, outputUp, outputDown }

final class ShiftModel: ObservableObject {
    @Published var gamepadName: String?
    @Published private(set) var source: ControllerSource = .gamepad
    @Published var gamepadBinding = GamepadBinding(rawValue: UserDefaults.standard.string(forKey: "gamepadBinding") ?? "") ?? .dpad {
        didSet { release(); bindGamepad(); UserDefaults.standard.set(gamepadBinding.rawValue, forKey: "gamepadBinding") }
    }
    @Published private(set) var outputMode: OutputMode = .myWhoosh
    @Published private(set) var outputArmed = false
    @Published var targetBundleID = "com.whoosh.whooshgame" { didSet { disarmOutput() } }
    @Published var learningText: String?
    @Published var targets: [TrainingTarget] = []
    @Published var inputUp = KeyBinding.load("inputUp", fallback: .up)
    @Published var inputDown = KeyBinding.load("inputDown", fallback: .down)
    @Published var outputUp = KeyBinding.load("outputUp", fallback: .up)
    @Published var outputDown = KeyBinding.load("outputDown", fallback: .down)
    @Published var connectionText = "Verbindung wird vorbereitet …"
    @Published var appName: String?
    @Published var networkReady = false
    @Published private var networkConnected = false
    @Published var lastInput = "Noch keine Eingabe"
    @Published var lastDirection: ShiftAction?
    @Published var commands = 0
    @Published var reversed = UserDefaults.standard.bool(forKey: "reversed") {
        didSet { release(); UserDefaults.standard.set(reversed, forKey: "reversed") }
    }
    @Published var holdToRepeat = UserDefaults.standard.object(forKey: "holdToRepeat") as? Bool ?? true {
        didSet { release(); UserDefaults.standard.set(holdToRepeat, forKey: "holdToRepeat") }
    }
    let click = ClickBluetooth()
    let keyboard = KeyboardBridge()
    private let bridge = DeviceBridge()
    private var controller: GCController?
    private var latch = DirectionLatch()
    private var remoteKeys = RemoteKeys()
    private var observers: [NSObjectProtocol] = []
    private var workspaceObservers: [NSObjectProtocol] = []
    private var repeatTimer: Timer?
    private var started = false
    private var inputGeneration = 0
    private var pulseAction: ShiftAction?
    private var learning: LearnTarget?
    var useClick: Bool { source.clickVersion != nil }
    var targetPID: pid_t? { NSRunningApplication.runningApplications(withBundleIdentifier: targetBundleID).first(where: { !$0.isTerminated })?.processIdentifier }
    var connected: Bool { outputMode == .myWhoosh ? networkConnected : outputArmed && keyboard.trusted && targetPID != nil }
    var controllerName: String? {
        if useClick { return click.readyName }
        if source == .keyboard { return keyboard.trusted ? "Tastatur / HID-Fernbedienung" : nil }
        return gamepadName
    }
    var ready: Bool { controllerName != nil && connected }
    var outputTitle: String { outputMode == .myWhoosh ? "MyWhoosh" : "Tastenausgabe" }
    var outputStatus: String {
        if outputMode == .myWhoosh { return connected ? appName ?? "Verbunden" : "Noch nicht verbunden" }
        if !keyboard.trusted { return "Bedienungshilfen erforderlich" }
        if targetPID == nil { return "Ziel-App zuerst starten" }
        return outputArmed ? "Aktiv · ausgewählte App" : "Deaktiviert"
    }
    var headline: String { ready ? "Bereit zum Fahren" : (controllerName == nil ? "Controller verbinden" : "Ausgabe verbinden") }
    var subtitle: String {
        if useClick && controllerName == nil { return click.message }
        if source == .keyboard { return keyboard.trusted ? "Nur die zwei angelernten Tasten werden als Schaltbefehle ausgewertet." : "Für Fernbedienungen im Hintergrund: Bedienungshilfen für Shift erlauben." }
        if ready && useClick { return "\(source.title): Plus und Minus schalten. Die Richtung lässt sich tauschen." }
        if controllerName == nil { return "Gamepad mit macOS verbinden oder Click direkt in Shift suchen." }
        if ready { return gamepadBinding.title + " · Richtung und Wiederholung anpassbar." }
        return outputMode == .myWhoosh ? "In MyWhoosh bei den Controllern „Shift“ auswählen." : "Ziel-App und zwei Tasten wählen; Ausgabe anschließend aktivieren."
    }
    func start() {
        guard !started else { return }; started = true
        GCController.shouldMonitorBackgroundEvents = true
        click.onChange = { [weak self] in
            guard let self else { return }
            if self.useClick && self.click.readyName == nil { self.release() }
            self.objectWillChange.send()
        }
        click.onButtons = { [weak self] buttons in guard let self, self.useClick else { return }; self.input(x: buttons.direction) }
        keyboard.onKey = { [weak self] code, flags, down in
            guard let self, self.source == .keyboard,
                  let direction = self.remoteKeys.update(code: code, modifiers: flags, down: down, upBinding: self.inputUp, downBinding: self.inputDown) else { return }
            self.input(x: direction)
        }
        keyboard.onLearn = { [weak self] binding in self?.finishLearning(binding) }
        bridge.onChange = { [weak self] in
            guard let self else { return }
            self.connectionText = self.bridge.message; self.networkReady = self.bridge.listening
            self.networkConnected = self.bridge.connected && self.bridge.canShift; self.appName = self.bridge.connectedName
            if self.outputMode == .myWhoosh && !self.networkConnected { self.release() }
        }
        bridge.onDelivery = { [weak self] action in self?.delivered(action) }
        for name in [Notification.Name.GCControllerDidConnect, Notification.Name.GCControllerDidDisconnect] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.refreshController() })
        }
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification, NSWorkspace.sessionDidResignActiveNotification] {
            workspaceObservers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.disarmOutput(); self?.release(); self?.refreshTargets()
            })
        }
        refreshTargets(); refreshController(); bridge.start()
    }
    func refreshTargets() {
        targets = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular && $0.bundleIdentifier != Bundle.main.bundleIdentifier }
            .compactMap { app in guard let id = app.bundleIdentifier else { return nil }; return TrainingTarget(id: id, name: app.localizedName ?? id) }
            .sorted { $0.name < $1.name }
        if source == .keyboard && keyboard.trusted { keyboard.start() }
        objectWillChange.send()
    }
    private func refreshController() {
        let next = GCController.controllers().first { $0.extendedGamepad != nil }
        if controller === next { return }; release()
        clearHandlers(); controller = next
        gamepadName = next?.vendorName ?? (next == nil ? nil : "Gamepad")
        next?.handlerQueue = .main; bindGamepad()
    }
    private func clearHandlers() {
        guard let g = controller?.extendedGamepad else { return }
        g.dpad.valueChangedHandler = nil; g.leftThumbstick.valueChangedHandler = nil; g.rightThumbstick.valueChangedHandler = nil
        for b in [g.leftShoulder, g.rightShoulder, g.leftTrigger, g.rightTrigger, g.buttonX, g.buttonB] { b.valueChangedHandler = nil }
    }
    private func bindGamepad() {
        clearHandlers()
        guard let g = controller?.extendedGamepad else { return }
        let axis: (GCControllerDirectionPad, Float, Float) -> Void = { [weak self] _, x, _ in
            guard let self, self.source == .gamepad else { return }; self.input(x: x)
        }
        switch gamepadBinding {
        case .dpad: g.dpad.valueChangedHandler = axis
        case .leftStick: g.leftThumbstick.valueChangedHandler = axis
        case .rightStick: g.rightThumbstick.valueChangedHandler = axis
        default:
            let pair: (GCControllerButtonInput, GCControllerButtonInput)
            switch gamepadBinding {
            case .shoulders: pair = (g.leftShoulder, g.rightShoulder)
            case .triggers: pair = (g.leftTrigger, g.rightTrigger)
            default: pair = (g.buttonX, g.buttonB)
            }
            let changed: GCControllerButtonValueChangedHandler = { [weak self, weak left = pair.0, weak right = pair.1] _, _, _ in
                guard let self, self.source == .gamepad, let left, let right else { return }
                self.input(x: left.isPressed == right.isPressed ? 0 : (right.isPressed ? 1 : -1))
            }
            pair.0.valueChangedHandler = changed; pair.1.valueChangedHandler = changed
        }
    }
    private func delivered(_ action: ShiftAction) { commands += 1; lastInput = action.title + " gesendet" }
    private func send(_ action: ShiftAction, pressed: Bool) {
        if outputMode == .myWhoosh { bridge.shift(action, pressed: pressed) }
        else if outputArmed && keyboard.send(action == .up ? outputUp : outputDown, down: pressed), pressed { delivered(action) }
    }
    private func input(x: Float) {
        let changes = latch.update(x: x, inverted: reversed); guard !changes.isEmpty else { return }
        if let pulseAction { send(pulseAction, pressed: false); self.pulseAction = nil }
        inputGeneration += 1; repeatTimer?.invalidate(); repeatTimer = nil
        for (action, pressed) in changes {
            send(action, pressed: pressed)
            if pressed { lastDirection = action; if !connected { lastInput = action.title + " erkannt · Ausgabe noch nicht verbunden" } }
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
        guard connected else { lastInput = "Zuerst die Ausgabe verbinden"; return }
        release(); let generation = inputGeneration
        send(action, pressed: true); pulseAction = action; lastDirection = action
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self, self.inputGeneration == generation else { return }; self.send(action, pressed: false); self.pulseAction = nil
        }
    }
    private func repeatShift(_ action: ShiftAction) {
        let generation = inputGeneration; send(action, pressed: false)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) { [weak self] in
            guard let self, generation == self.inputGeneration, self.connected, self.latch.held == action else { return }
            self.send(action, pressed: true)
        }
    }
    private func release() {
        inputGeneration += 1; repeatTimer?.invalidate(); repeatTimer = nil
        if let held = latch.held { send(held, pressed: false) }
        if let pulseAction { send(pulseAction, pressed: false); self.pulseAction = nil }
        keyboard.releaseAll(); latch = DirectionLatch(); remoteKeys.reset()
    }
    func selectSource(_ next: ControllerSource) {
        release(); cancelLearning(); click.stop(); source = next
        if let version = next.clickVersion { click.selectVersion(version) }
        if next == .keyboard { keyboard.start() } else { keyboard.stopMonitoring() }
    }
    func scanClick() { guard let version = source.clickVersion else { return }; click.scan(version: version) }
    func selectOutput(_ next: OutputMode) { release(); disarmOutput(); outputMode = next }
    func armOutput() {
        release()
        guard keyboard.trusted else { lastInput = "Bedienungshilfen für Shift erlauben"; return }
        guard let pid = targetPID else { lastInput = "Ziel-App zuerst starten"; return }
        keyboard.arm(pid); outputArmed = true
    }
    func disarmOutput() { release(); outputArmed = false; keyboard.arm(nil) }
    func learn(_ target: LearnTarget) {
        release(); disarmOutput(); learning = target
        learningText = "Jetzt die gewünschte Taste drücken. Esc bricht ab."; keyboard.start(); keyboard.learn()
    }
    func cancelLearning() {
        learning = nil; learningText = nil; keyboard.cancelLearn()
        if source != .keyboard { keyboard.stopMonitoring() }
    }
    private func finishLearning(_ key: KeyBinding) {
        guard let target = learning else { return }
        if key.code == 53 { cancelLearning(); return }
        switch target {
        case .inputUp: guard key.code != inputDown.code else { lastInput = "Zwei verschiedene Tasten wählen"; cancelLearning(); return }; inputUp = key; key.save("inputUp")
        case .inputDown: guard key.code != inputUp.code else { lastInput = "Zwei verschiedene Tasten wählen"; cancelLearning(); return }; inputDown = key; key.save("inputDown")
        case .outputUp: outputUp = key; key.save("outputUp")
        case .outputDown: outputDown = key; key.save("outputDown")
        }
        cancelLearning(); if source != .keyboard { keyboard.stopMonitoring() }
    }
    func reconnect() { release(); bridge.start(); refreshController(); refreshTargets() }
    func stop() {
        release(); clearHandlers(); observers.forEach(NotificationCenter.default.removeObserver); observers = []
        workspaceObservers.forEach(NSWorkspace.shared.notificationCenter.removeObserver); workspaceObservers = []
        click.stop(); keyboard.stop(); bridge.stop(); started = false
    }
    func openMyWhoosh() {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.whoosh.whooshgame") {
            NSWorkspace.shared.openApplication(at: url, configuration: .init())
        } else { NSWorkspace.shared.open(URL(string: "https://www.mywhoosh.com/get-mywhoosh/")!) }
    }
    func openBluetooth() { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.BluetoothSettings")!) }
}

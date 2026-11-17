import AppKit
import Combine
import GameController
import UniformTypeIdentifiers

struct TrainingTarget: Identifiable { let id: String; let name: String }
enum LearnTarget { case inputUp, inputDown, outputUp, outputDown }

final class ShiftModel: ObservableObject {
    @Published var showSetup = !UserDefaults.standard.bool(forKey: "setupSeen")
    @Published private(set) var setupStep: SetupStep = .controller
    @Published private(set) var buttonCheck = ButtonCheck()
    @Published var profileName = "Mein Setup"
    @Published var notice: String?
    var setupReadiness: SetupReadiness {
        SetupReadiness(pairConnected: click.pairReady, appConnected: networkConnected, buttonsTested: buttonCheck.complete)
    }
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
    @Published var inputSequence = 0
    @Published var reversed = UserDefaults.standard.bool(forKey: "reversed") {
        didSet { release(); UserDefaults.standard.set(reversed, forKey: "reversed") }
    }
    @Published var holdToRepeat = UserDefaults.standard.object(forKey: "holdToRepeat") as? Bool ?? true {
        didSet { release(); UserDefaults.standard.set(holdToRepeat, forKey: "holdToRepeat") }
    }
    let click = ClickBluetooth()
    let keyboard = KeyboardBridge()
    let bluetoothOutput = BluetoothOutput()
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
    private var lastBluetoothConnected = false
    private var learning: LearnTarget?
    var useClick: Bool { source.clickVersion != nil }
    var targetPID: pid_t? { NSRunningApplication.runningApplications(withBundleIdentifier: targetBundleID).first(where: { !$0.isTerminated })?.processIdentifier }
    var connected: Bool {
        switch outputMode { case .myWhoosh: return networkConnected; case .bluetooth: return bluetoothOutput.connected; case .keyboard: return outputArmed && keyboard.trusted && targetPID != nil }
    }
    var controllerName: String? {
        if useClick { return click.readyName }
        if source == .keyboard { return keyboard.trusted ? "Tastatur / HID-Fernbedienung" : nil }
        return gamepadName
    }
    var ready: Bool { controllerName != nil && connected && (source != .clickV2 || (click.pairReady && buttonCheck.complete)) }
    var outputTitle: String { outputMode == .myWhoosh ? "MyWhoosh" : (outputMode == .bluetooth ? "Bluetooth" : "Tastenausgabe") }
    var outputStatus: String {
        if outputMode == .myWhoosh { return connected ? appName ?? "Verbunden" : "Noch nicht verbunden" }
        if outputMode == .bluetooth { return bluetoothOutput.message }
        if !keyboard.trusted { return "Bedienungshilfen erforderlich" }
        if targetPID == nil { return "Ziel-App zuerst starten" }
        return outputArmed ? "Aktiv · ausgewählte App" : "Deaktiviert"
    }
    var headline: String {
        if source == .clickV2 && !click.pairReady { return "Beide Clicks verbinden" }
        if source == .clickV2 && connected && !buttonCheck.complete { return "Plus und Minus prüfen" }
        return ready ? "Bereit zum Fahren" : (controllerName == nil ? "Controller verbinden" : "Ausgabe verbinden")
    }
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
            if self.source == .clickV2 && !self.click.pairReady { self.buttonCheck.reset() }
            self.objectWillChange.send()
        }
        click.onButtons = { [weak self] buttons in
            guard let self, self.useClick else { return }
            if self.source == .clickV2 && self.click.pairReady && self.connected { self.buttonCheck.observe(buttons) }
            self.input(x: buttons.direction)
        }
        keyboard.onKey = { [weak self] code, flags, down in
            guard let self, self.source == .keyboard,
                  let direction = self.remoteKeys.update(code: code, modifiers: flags, down: down, upBinding: self.inputUp, downBinding: self.inputDown) else { return }
            self.input(x: direction)
        }
        bluetoothOutput.onChange = { [weak self] in
            guard let self else { return }
            let connected = self.bluetoothOutput.connected
            if self.outputMode == .bluetooth && connected != self.lastBluetoothConnected {
                self.release()
                if !connected { self.buttonCheck.reset() }
            }
            self.lastBluetoothConnected = connected
            self.objectWillChange.send()
        }
        bluetoothOutput.onDelivery = { [weak self] action in self?.delivered(action) }
        keyboard.onLearn = { [weak self] binding in self?.finishLearning(binding) }
        bridge.onChange = { [weak self] in
            guard let self else { return }
            self.connectionText = self.bridge.message; self.networkReady = self.bridge.listening
            self.networkConnected = self.bridge.connected && self.bridge.canShift; self.appName = self.bridge.connectedName
            if self.outputMode == .myWhoosh && !self.networkConnected { self.release(); self.buttonCheck.reset() }
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
        if let data = UserDefaults.standard.data(forKey: "savedProfile"),
           let saved = try? JSONDecoder().decode(ShiftProfile.self, from: data).validated() { applyProfile(saved) }
        else if showSetup { configureVitus() }
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
        else if outputMode == .bluetooth { bluetoothOutput.shift(action, pressed: pressed) }
        else if outputArmed && keyboard.send(action == .up ? outputUp : outputDown, down: pressed), pressed { delivered(action) }
    }
    private func input(x: Float) {
        let changes = latch.update(x: x, inverted: reversed); guard !changes.isEmpty else { return }
        if let pulseAction { send(pulseAction, pressed: false); self.pulseAction = nil }
        inputGeneration += 1; repeatTimer?.invalidate(); repeatTimer = nil
        for (action, pressed) in changes {
            send(action, pressed: pressed)
            if pressed { inputSequence += 1; lastDirection = action; if !connected { lastInput = action.title + " erkannt · Ausgabe noch nicht verbunden" } }
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
        inputSequence += 1; send(action, pressed: true); pulseAction = action; lastDirection = action
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
        release(); cancelLearning(); buttonCheck.reset(); click.stop(); source = next
        if let version = next.clickVersion { click.selectVersion(version) }
        if next == .keyboard { keyboard.start() } else { keyboard.stopMonitoring() }
    }
    func scanClick() { guard let version = source.clickVersion else { return }; click.scan(version: version) }
    func selectOutput(_ next: OutputMode) {
        release(); disarmOutput(); bluetoothOutput.stop(); outputMode = next
        if next == .bluetooth { bluetoothOutput.start() }
    }
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
    func configureVitus() {
        disarmOutput(); selectOutput(.myWhoosh); selectSource(.clickV2)
        reversed = false; holdToRepeat = true; profileName = "MyWhoosh · beide Click V2"
        setupStep = .controller; buttonCheck.reset()
    }
    func beginSetup() { configureVitus(); showSetup = true }
    func advanceSetup() {
        guard setupReadiness.permits(setupStep) else { return }
        if setupStep == .controller { setupStep = .app }
        else if setupStep == .app { buttonCheck.reset(); setupStep = .test }
        else { saveProfile(); showSetup = false; UserDefaults.standard.set(true, forKey: "setupSeen") }
    }
    func backSetup() {
        if setupStep == .test { setupStep = .app }
        else if setupStep == .app { setupStep = .controller }
    }
    func skipSetup() { showSetup = false; UserDefaults.standard.set(true, forKey: "setupSeen") }
    func resetButtonTest() { buttonCheck.reset() }
    private var currentProfile: ShiftProfile {
        ShiftProfile(name: profileName, source: source, gamepad: gamepadBinding, reversed: reversed,
                     holdToRepeat: holdToRepeat, inputUp: inputUp, inputDown: inputDown, outputUp: outputUp, outputDown: outputDown)
    }
    func saveProfile() {
        do {
            let valid = try currentProfile.validated(); let data = try JSONEncoder().encode(valid)
            UserDefaults.standard.set(data, forKey: "savedProfile"); notice = "Profil gespeichert"
        } catch { notice = "Profil prüfen: Name und zwei verschiedene Eingabetasten sind nötig." }
    }
    private func applyProfile(_ p: ShiftProfile) {
        disarmOutput(); selectOutput(.myWhoosh); selectSource(p.source)
        gamepadBinding = p.gamepad; reversed = p.reversed; holdToRepeat = p.holdToRepeat
        inputUp = p.inputUp; inputDown = p.inputDown; outputUp = p.outputUp; outputDown = p.outputDown
        profileName = p.name
    }
    func exportProfile() {
        do {
            let valid = try currentProfile.validated(); let panel = NSSavePanel()
            panel.allowedContentTypes = [.json]; panel.nameFieldStringValue = "Shift-Profil.json"
            guard panel.runModal() == .OK, let url = panel.url else { return }
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(valid).write(to: url, options: .atomic); notice = "Profil exportiert · ohne Freigaben oder Gerätekennungen"
        } catch { notice = "Profil konnte nicht exportiert werden." }
    }
    func importProfile() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            guard let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > 0, size <= 16384 else { throw ShiftProfile.ProfileError.invalid }
            let data = try Data(contentsOf: url); guard data.count <= 16384 else { throw ShiftProfile.ProfileError.invalid }
            let profile = try JSONDecoder().decode(ShiftProfile.self, from: data).validated()
            applyProfile(profile); saveProfile(); notice = "Profil geladen. Bluetooth und Freigaben am eigenen Mac einrichten."
        } catch { notice = "Keine gültige Shift-Profildatei. Bestehendes Profil bleibt erhalten." }
    }
    func exportDiagnostics() {
        let panel = NSSavePanel(); panel.allowedContentTypes = [.json]; panel.nameFieldStringValue = "Shift-Diagnose.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let data: [String: Any] = ["version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
                                 "system": ProcessInfo.processInfo.operatingSystemVersionString,
                                 "controller": source.rawValue, "output": outputMode.rawValue,
                                 "leftConnected": click.leftReady, "rightConnected": click.rightReady,
                                 "plusTested": buttonCheck.plus, "minusTested": buttonCheck.minus,
                                 "trainingAppConnected": networkConnected, "keyboardPermission": keyboard.trusted,
                                 "networkStatus": connectionText]
        do { try JSONSerialization.data(withJSONObject: data, options: [.prettyPrinted, .sortedKeys]).write(to: url, options: .atomic); notice = "Diagnose gespeichert · ohne Geräte-IDs, Konten oder Trainingsdaten" }
        catch { notice = "Diagnose konnte nicht gespeichert werden." }
    }
    func reconnect() { release(); bridge.start(); refreshController(); refreshTargets() }
    func stop() {
        release(); clearHandlers(); observers.forEach(NotificationCenter.default.removeObserver); observers = []
        workspaceObservers.forEach(NSWorkspace.shared.notificationCenter.removeObserver); workspaceObservers = []
        VirtualTrainerServer.shared.stop(); click.stop(); bluetoothOutput.stop(); keyboard.stop(); bridge.stop(); started = false
    }
    func openMyWhoosh() {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.whoosh.whooshgame") {
            NSWorkspace.shared.openApplication(at: url, configuration: .init())
        } else { NSWorkspace.shared.open(URL(string: "https://www.mywhoosh.com/get-mywhoosh/")!) }
    }
    func openBluetooth() { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.BluetoothSettings")!) }
}

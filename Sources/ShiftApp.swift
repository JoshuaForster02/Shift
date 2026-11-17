import SwiftUI
import AppKit

@main
struct ShiftApp: App {
    @StateObject private var model = ShiftModel()
    var body: some Scene {
        WindowGroup("Shift") {
            Group {
                if model.showSetup { SetupView(model: model) } else { ShiftView(model: model) }
            }
                .frame(minWidth: 460, idealWidth: 500, maxWidth: 660, minHeight: 600, idealHeight: 700)
                .preferredColorScheme(.dark)
                .onAppear { model.start() }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in model.stop() }
                .onOpenURL { url in
                    guard url.scheme == "shift", url.host == "open" else { return }
                    NSApp.activate(ignoringOtherApps: true)
                }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 500, height: 700)
        .commands {
            CommandMenu("Fahren") {
                Button("Hochschalten") { model.pulse(.up) }.keyboardShortcut(.upArrow, modifiers: .command)
                Button("Runterschalten") { model.pulse(.down) }.keyboardShortcut(.downArrow, modifiers: .command)
                Divider()
                Button("Erneut verbinden") { model.reconnect() }.keyboardShortcut("r", modifiers: .command)
                Button("MyWhoosh öffnen") { model.openMyWhoosh() }.keyboardShortcut("o", modifiers: .command)
            }
        }
        MenuBarExtra("Shift", systemImage: "bicycle") {
            Text(model.headline)
            Divider()
            Button("Shift öffnen") { NSApp.activate(ignoringOtherApps: true); NSApp.windows.first?.makeKeyAndOrderFront(nil) }
            Button("MyWhoosh öffnen") { model.openMyWhoosh() }
            Button("Beenden") { model.stop(); NSApp.terminate(nil) }.keyboardShortcut("q")
        }
    }
}

struct ShiftView: View {
    @ObservedObject var model: ShiftModel
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @AppStorage("futuristicMotion") private var motionMode = "system"
    private var reduceMotion: Bool { motionMode == "off" || (motionMode != "on" && systemReduceMotion) }
    @State private var showHelp = false
    @State private var showAdvanced = false
    private let accent = Color(red: 0.32, green: 0.65, blue: 1)
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                HStack {
                    Image(systemName: "bicycle").font(.system(size: 20, weight: .medium)).foregroundStyle(accent)
                    Text("Shift").font(.system(size: 17, weight: .semibold))
                    Spacer()
                    Button("Einrichten") { model.beginSetup() }.font(.system(size: 11)).buttonStyle(.borderless)
                    Text("MAC").font(.system(size: 10, weight: .medium, design: .monospaced)).foregroundStyle(.secondary)
                }.padding(.top, 14)
                VStack(alignment: .leading, spacing: 10) {
                    Text(model.headline).font(.system(size: 30, weight: .semibold, design: .rounded)).tracking(-0.7)
                    Text(model.subtitle).font(.system(size: 13)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                if model.source == .clickV2 {
                    HStack(spacing: 20) {
                        Label("Links · −", systemImage: model.click.leftReady ? "checkmark.circle.fill" : "circle")
                        Label("Rechts · +", systemImage: model.click.rightReady ? "checkmark.circle.fill" : "circle")
                    }.font(.system(size: 12)).foregroundStyle(.secondary)
                    HStack {
                        Button(model.click.scanning ? "Suche läuft …" : "Beide suchen") { model.scanClick() }.disabled(model.click.scanning)
                        if model.click.uniquePairAvailable { Button("Beide verbinden") { model.click.connectPair() } }
                    }
                }
                DisclosureGroup("Controller und Ausgabe anpassen", isExpanded: $showAdvanced) {
                    VStack(alignment: .leading, spacing: 18) {
                Picker("Controller", selection: Binding(get: { model.source }, set: { model.selectSource($0) })) {
                    ForEach(ControllerSource.allCases) { source in Text(source.title).tag(source) }
                }.pickerStyle(.segmented)
                if model.source == .gamepad {
                    Picker("Tastenbelegung", selection: $model.gamepadBinding) {
                        ForEach(GamepadBinding.allCases) { binding in Text(binding.title).tag(binding) }
                    }
                }
                if model.source == .keyboard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Für Anki-Remotes und Bluetooth-HID-Tastaturen. Nur die beiden angelernten Tasten werden im Hintergrund ausgewertet.").font(.system(size: 11)).foregroundStyle(.secondary)
                        HStack {
                            Button("Hoch: \(model.inputUp.title)") { model.learn(.inputUp) }
                            Button("Runter: \(model.inputDown.title)") { model.learn(.inputDown) }
                        }
                        if !model.keyboard.trusted {
                            Button("Bedienungshilfen erlauben") { model.keyboard.askPermission() }
                        }
                        Button("Zugriff erneut prüfen") { model.refreshTargets() }
                    }
                }
                if model.useClick {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(model.click.message).font(.system(size: 11)).foregroundStyle(.secondary)
                            Spacer()
                            Button(model.click.scanning ? "Sucht …" : "Click suchen") { model.scanClick() }.disabled(model.click.scanning)
                        }
                        ForEach(model.click.devices) { device in
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(device.name).font(.system(size: 12, weight: .medium))
                                    Text(device.status).font(.system(size: 11)).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button(device.connected ? "Trennen" : "Verbinden") {
                                    if device.connected { model.click.disconnect(device.id) } else { model.click.connect(device.id) }
                                }
                            }
                        }
                        DisclosureGroup("Firmware und Aktivierung") {
                            Text("Click V1 wird mit unverschlüsseltem Protokoll unterstützt. Verschlüsselte V1-Firmware ist noch nicht unterstützt. Bei V2 ist je nach Firmware eine zeitlich begrenzte Aktivierung durch Zwift nötig: beide Controller dort verbinden und Tasten prüfen, Zwift vollständig schließen und hier erneut verbinden. Shift erneuert diese Freigabe nicht automatisch. Click V2 ist eine Beta-Anbindung; ein echter Fahrtest steht noch aus.")
                                .font(.system(size: 11)).foregroundStyle(.secondary).padding(.top, 5)
                        }.font(.system(size: 11))
                    }
                }
                Picker("Ausgabe", selection: Binding(get: { model.outputMode }, set: { model.selectOutput($0) })) {
                    ForEach(OutputMode.allCases) { mode in Text(mode.title).tag(mode) }
                }
                if model.outputMode == .bluetooth {
                    Text("Shift emuliert einen OpenBikeControl-Bluetooth-Controller. Nur Apps mit diesem Protokoll können ihn verwenden; das ist keine Zwift- oder Trainer-Emulation. Für MyWhoosh im Einrichtungsassistenten die Netzwerk-Ausgabe verwenden. Bluetooth-Ausgabe ist noch nicht mit einer echten Trainings-App geprüft.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                if model.outputMode == .keyboard {
                    VStack(alignment: .leading, spacing: 10) {
                        Picker("Ziel-App", selection: $model.targetBundleID) {
                            if !model.targets.contains(where: { $0.id == model.targetBundleID }) {
                                Text("Ziel-App starten").tag(model.targetBundleID)
                            }
                            ForEach(model.targets) { target in Text(target.name).tag(target.id) }
                        }
                        HStack {
                            Button("Hoch: \(model.outputUp.title)") { model.learn(.outputUp) }
                            Button("Runter: \(model.outputDown.title)") { model.learn(.outputDown) }
                        }
                        HStack {
                            Button("Apps / Zugriff prüfen") { model.refreshTargets() }
                            if model.keyboard.trusted {
                                Button(model.outputArmed ? "Ausgabe deaktivieren" : "Tastenausgabe aktivieren") {
                                    if model.outputArmed { model.disarmOutput() } else { model.armOutput() }
                                }
                            } else {
                                Button("Bedienungshilfen erlauben") { model.keyboard.askPermission() }
                            }
                        }
                        Text("Sendet nur an die ausgewählte laufende App. Die App muss diese Tasten unterstützen. Tastenausgabe allein erzeugt keine virtuellen Gänge.")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
                if let learning = model.learningText {
                    HStack { Text(learning); Spacer(); Button("Abbrechen") { model.cancelLearning() } }.font(.system(size: 12))
                }
                    }.padding(.top, 12)
                }.font(.system(size: 12))
                VStack(spacing: 0) {
                    status("gamecontroller", title: "Controller", value: model.controllerName ?? "Nicht verbunden", active: model.controllerName != nil)
                    Divider().opacity(0.5)
                    status("antenna.radiowaves.left.and.right", title: model.outputTitle, value: model.outputStatus, active: model.connected)
                }
                HStack(spacing: 24) {
                    direction(.down, arrow: "arrow.left", key: model.reversed ? "Rechts" : "Links")
                    Rectangle().fill(.white.opacity(0.09)).frame(width: 1, height: 64)
                    direction(.up, arrow: "arrow.right", key: model.reversed ? "Links" : "Rechts")
                }.frame(maxWidth: .infinity).padding(.vertical, 8)
                VStack(spacing: 13) {
                    Toggle("Gedrückt halten: mehrere Gänge", isOn: $model.holdToRepeat).toggleStyle(.switch).controlSize(.small)
                    Toggle("Schaltrichtung tauschen", isOn: $model.reversed).toggleStyle(.switch).controlSize(.small)
                }.font(.system(size: 12))
                HStack {
                    Circle().fill(model.ready ? accent : .gray).frame(width: 5, height: 5)
                    Text(model.lastInput).lineLimit(2).font(.system(size: 11)).foregroundStyle(.secondary)
                    Spacer()
                    Text("\(model.commands)").font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                }.accessibilityElement(children: .combine)
                HStack {
                    Button(model.useClick ? "MyWhoosh öffnen" : (model.controllerName == nil ? "Bluetooth öffnen" : "MyWhoosh öffnen")) {
                        if model.controllerName == nil && !model.useClick { model.openBluetooth() } else { model.openMyWhoosh() }
                    }.buttonStyle(.borderedProminent).tint(accent).controlSize(.large)
                    Spacer()
                    Button { model.reconnect() } label: { Image(systemName: "arrow.clockwise") }.help("Erneut verbinden · ⌘R")
                    Button { showHelp.toggle() } label: { Image(systemName: "questionmark.circle") }.help("Einrichtung")
                }.buttonStyle(.borderless)
                if showHelp {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("1  Gamepad/HID in macOS verbinden; Click V1/V2 direkt in Shift suchen.")
                        Text("2  Lokales Netzwerk für Shift erlauben.")
                        Text("3  In MyWhoosh „Shift“ als Controller auswählen und MyShift aktivieren.")
                        Text("Mac und Trainings-App müssen im selben lokalen Netzwerk sein. Shift sendet ausschließlich Controller-Befehle; es ersetzt keinen Smart-Trainer.")
                            .foregroundStyle(.secondary)
                    }.font(.system(size: 12)).transition(.opacity)
                }
                DisclosureGroup("Profil und Diagnose") {
                    VStack(alignment: .leading, spacing: 10) {
                        Picker("Animationen", selection: $motionMode) {
                            Text("Systemvorgabe").tag("system"); Text("Voll").tag("on"); Text("Reduziert").tag("off")
                        }
                        TextField("Profilname", text: $model.profileName).textFieldStyle(.roundedBorder)
                        HStack {
                            Button("Speichern") { model.saveProfile() }
                            Button("Exportieren") { model.exportProfile() }
                            Button("Importieren") { model.importProfile() }
                        }
                        Button("Verbindungsdiagnose speichern") { model.exportDiagnostics() }
                        if let notice = model.notice { Text(notice).foregroundStyle(.secondary) }
                        Text("Ein Profil überträgt Belegungen, keine Bluetooth-Geräte, Freigaben oder aktivierte Tastenausgabe.").foregroundStyle(.secondary)
                    }.font(.system(size: 11)).padding(.top, 6)
                }.font(.system(size: 11))
                DisclosureGroup("Controller und Grenzen") {
                    Text("Enthalten: Click V1 (unverschlüsselt), Click V2 (Aktivierung ggf. nötig), macOS-Gamepads mit sechs Belegungen sowie Tastatur-/HID-Remotes mit zwei anlernbaren Tasten. Ausgabe per MyWhoosh-Netzwerk oder als Tasten an eine ausgewählte Mac-App. Zusätzlich enthalten: Zwift Ride mit älterem unverschlüsseltem Protokoll (Beta). Noch nicht enthalten: Zwift Play und verschlüsselter V1, Di2, SRAM AXS, CYCPLUS, Thinkrider, Wahoo-Bike, Elite, Wheeltop, reine Medien-Tasten, ANT+, Zwift-Geräteemulation oder direkte Trainer-Widerstandssteuerung. OpenBikeControl-Bluetooth-Ausgabe ist als Beta enthalten. Tastatur-Modi dieser Geräte können ggf. über HID genutzt werden. Protokolltests vorhanden; echte Gerätekompatibilität muss je Modell geprüft werden.")
                        .font(.system(size: 11)).foregroundStyle(.secondary).padding(.top, 5)
                }.font(.system(size: 11))
                HStack {
                    Text("1.4.0 · Lokal · Ohne Konto")
                    Spacer()
                    Link("Quellcode", destination: URL(string: "https://github.com/JoshuaForster02/Shift")!)
                }.font(.system(size: 10)).foregroundStyle(.tertiary)
            }.padding(.horizontal, 30).padding(.bottom, 24)
        }
        .background { CircuitBackdrop(emphasis: model.ready ? 1 : 0.65) }
        .tint(accent)
        .animation(reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.8), value: model.ready)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: showHelp)
    }
    private func status(_ symbol: String, title: String, value: String, active: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).foregroundStyle(active ? accent : .gray).frame(width: 22)
            Text(title).font(.system(size: 13, weight: .medium))
            Spacer()
            Text(value).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
        }.padding(.vertical, 15)
    }
    private func direction(_ action: ShiftAction, arrow: String, key: String) -> some View {
        Button { model.pulse(action) } label: {
            VStack(spacing: 10) {
                SignalGlyph(symbol: arrow, active: model.lastDirection == action, pulse: model.lastDirection == action ? model.inputSequence : 0)
                Text(action == .up ? "Hoch" : "Runter").font(.system(size: 14, weight: .semibold))
                Text(model.useClick ? (action == .up ? (model.reversed ? "Click −" : "Click +") : (model.reversed ? "Click +" : "Click −")) : (model.source == .keyboard ? (action == .up ? model.inputUp.title : model.inputDown.title) : model.gamepadBinding.title)).font(.system(size: 10)).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity).contentShape(Rectangle())
        }.buttonStyle(.plain).disabled(!model.connected).help(action.title)
    }
}

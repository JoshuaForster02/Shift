import SwiftUI

struct SetupView: View {
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @AppStorage("futuristicMotion") private var motionMode = "system"
    private var reduceMotion: Bool { motionMode == "off" || (motionMode != "on" && systemReduceMotion) }
    @ObservedObject var model: ShiftModel
    private let accent = Color(red: 0.32, green: 0.65, blue: 1)
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack {
                    Label("Shift", systemImage: "bicycle").font(.system(size: 17, weight: .semibold))
                    Spacer(); Text("EINRICHTUNG").font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                }.padding(.top, 14)
                HStack(spacing: 0) {
                    ForEach(SetupStep.allCases, id: \.rawValue) { step in
                        VStack(alignment: .leading, spacing: 8) {
                            Rectangle().fill(step.rawValue <= model.setupStep.rawValue ? accent : Color.white.opacity(0.12)).frame(height: 2)
                            Text("\(step.rawValue + 1)  \(step.title)").font(.system(size: 11)).foregroundStyle(step == model.setupStep ? .primary : .secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                        if step != .test { Spacer().frame(width: 12) }
                    }
                }
                Text(title).font(.system(size: 31, weight: .semibold, design: .rounded)).tracking(-0.8)
                Text(subtitle).font(.system(size: 13)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Group {
                    if model.setupStep == .controller { controllers }
                    else if model.setupStep == .app { appConnection }
                    else { buttonTest }
                }
                .id(model.setupStep)
                .transition(reduceMotion ? .opacity : .asymmetric(insertion: .opacity.combined(with: .offset(y: 18)), removal: .opacity.combined(with: .offset(y: -8))))
                .animation(reduceMotion ? nil : .spring(response: 0.48, dampingFraction: 0.85), value: model.setupStep)
                Spacer(minLength: 6)
                HStack {
                    if model.setupStep != .controller { Button("Zurück") { model.backSetup() } }
                    Spacer()
                    Button(model.setupStep == .test ? "Fertig · losfahren" : "Weiter") { model.advanceSetup() }
                        .buttonStyle(.borderedProminent).controlSize(.large)
                        .disabled(!model.setupReadiness.permits(model.setupStep))
                }
                HStack {
                    Button("Andere Controller / manuell einrichten") { model.skipSetup() }
                    Spacer()
                    Menu("Animationen") {
                        Picker("Animationen", selection: $motionMode) {
                            Text("Systemvorgabe").tag("system"); Text("Voll").tag("on"); Text("Reduziert").tag("off")
                        }
                    }.menuStyle(.borderlessButton).frame(width: 84)
                    Link("Hilfe", destination: URL(string: "https://shift-kohl-chi.vercel.app/#einrichtung")!)
                }.font(.system(size: 11)).buttonStyle(.borderless).foregroundStyle(.secondary)
                Text("MyWhoosh · beide Zwift Click V2 · ohne Shift-Konto")
                    .font(.system(size: 10)).foregroundStyle(.tertiary)
            }.padding(.horizontal, 30).padding(.bottom, 24)
        }
        .background { CircuitBackdrop(emphasis: 0.8) }
        .tint(accent)
    }
    private var title: String {
        switch model.setupStep {
        case .controller: return "Zwei Clicks.\nEin Setup."
        case .app: return "Jetzt MyWhoosh."
        case .test: return "Plus. Minus.\nBereit."
        }
    }
    private var subtitle: String {
        switch model.setupStep {
        case .controller: return "Auf jedem Mac neu einrichten: beide Fernbedienungen aufwecken und Zwift vollständig schließen. Die Controller werden direkt hier verbunden."
        case .app: return "MyWhoosh öffnen. In der Geräteauswahl Shift als Controller auswählen und MyShift aktivieren. Mac und Trainingsgerät brauchen dasselbe lokale Netzwerk."
        case .test: return "Jetzt an den echten Fernbedienungen einmal + und einmal − drücken. Erst wenn beide Tasten ankommen und MyWhoosh verbunden bleibt, ist die Einrichtung geprüft."
        }
    }
    private var controllers: some View {
        VStack(alignment: .leading, spacing: 16) {
            checkRow("Links · −", detail: "Linke Fernbedienung", done: model.click.leftReady)
            Divider().opacity(0.4)
            checkRow("Rechts · +", detail: "Rechte Fernbedienung", done: model.click.rightReady)
            Text(model.click.message).font(.system(size: 11)).foregroundStyle(.secondary)
            HStack {
                Button(model.click.scanning ? "Suche läuft …" : "Beide suchen") { model.scanClick() }.disabled(model.click.scanning)
                if model.click.uniquePairAvailable {
                    Button("Beide verbinden") { model.click.connectPair() }.buttonStyle(.borderedProminent)
                }
            }
            ForEach(model.click.devices) { device in
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(device.name).font(.system(size: 12, weight: .medium))
                        Text(device.status).font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(device.connected ? "Trennen" : "Verbinden") {
                        if device.connected { model.click.disconnect(device.id) } else { model.click.connect(device.id) }
                    }
                }
            }
            DisclosureGroup("Eine Fernbedienung sendet keine Tasten?") {
                Text("Der linke Click V2 kann je nach Firmware eine zeitlich begrenzte Zwift-Freigabe brauchen. Beide Fernbedienungen in Zwift verbinden, Tasten prüfen, Zwift schließen und hier erneut verbinden. Shift erneuert diese Freigabe nicht automatisch. Bei mehreren gefundenen Paaren bitte einzeln auswählen.")
                    .font(.system(size: 11)).foregroundStyle(.secondary).padding(.top, 6)
            }.font(.system(size: 12))
        }
    }
    private var appConnection: some View {
        VStack(alignment: .leading, spacing: 16) {
            checkRow("Beide Fernbedienungen", detail: "Links und rechts verbunden", done: model.click.pairReady)
            Divider().opacity(0.4)
            checkRow("MyWhoosh", detail: model.outputStatus, done: model.connected)
            HStack {
                Button("MyWhoosh öffnen") { model.openMyWhoosh() }.buttonStyle(.borderedProminent)
                Button("Verbindung neu starten") { model.reconnect() }
            }
            DisclosureGroup("Shift erscheint nicht in MyWhoosh?") {
                Text("Lokales Netzwerk für Shift erlauben. Gäste-WLAN oder VPN können die Suche verhindern. MyShift einschalten und ältere Controller-Bridges schließen, damit keine doppelten Befehle gesendet werden.")
                    .font(.system(size: 11)).foregroundStyle(.secondary).padding(.top, 6)
            }.font(.system(size: 12))
        }
    }
    private var buttonTest: some View {
        VStack(alignment: .leading, spacing: 18) {
            checkRow("+ · schwererer Gang", detail: model.buttonCheck.plus ? "Echte Eingabe empfangen" : "Am rechten Click drücken", done: model.buttonCheck.plus)
            Divider().opacity(0.4)
            checkRow("− · leichterer Gang", detail: model.buttonCheck.minus ? "Echte Eingabe empfangen" : "Am linken Click drücken", done: model.buttonCheck.minus)
            Divider().opacity(0.4)
            checkRow("MyWhoosh verbunden", detail: model.outputStatus, done: model.connected && model.click.pairReady)
            Text(model.lastInput).font(.system(size: 12)).foregroundStyle(.secondary)
            Button("Tastentest zurücksetzen") { model.resetButtonTest() }.buttonStyle(.borderless).font(.system(size: 11))
            Text("Das bestätigt die Eingaben und die Verbindung. Ob die Gänge im laufenden Training reagieren, bitte bei der ersten Fahrt prüfen.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }
    private func checkRow(_ title: String, detail: String, done: Bool) -> some View {
        HStack(spacing: 12) {
            SignalGlyph(symbol: done ? "checkmark" : "circle.dotted", active: done, pulse: done ? 1 : 0).scaleEffect(0.65).frame(width: 38, height: 38)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 14, weight: .semibold))
                Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
        }.accessibilityElement(children: .combine)
    }
}

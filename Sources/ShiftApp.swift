import SwiftUI
import AppKit

@main
struct ShiftApp: App {
    @StateObject private var model = ShiftModel()
    var body: some Scene {
        WindowGroup("Shift") {
            ShiftView(model: model)
                .frame(minWidth: 440, idealWidth: 480, maxWidth: 620, minHeight: 560, idealHeight: 620)
                .preferredColorScheme(.dark)
                .onAppear { model.start() }
                .onOpenURL { url in
                    guard url.scheme == "shift", url.host == "open" else { return }
                    NSApp.activate(ignoringOtherApps: true)
                }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 480, height: 620)
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
    @State private var showHelp = false
    private let accent = Color(red: 0.32, green: 0.65, blue: 1)
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                HStack {
                    Image(systemName: "bicycle").font(.system(size: 20, weight: .medium)).foregroundStyle(accent)
                    Text("Shift").font(.system(size: 17, weight: .semibold))
                    Spacer()
                    Text("MAC").font(.system(size: 10, weight: .medium, design: .monospaced)).foregroundStyle(.secondary)
                }.padding(.top, 14)
                VStack(alignment: .leading, spacing: 10) {
                    Text(model.headline).font(.system(size: 30, weight: .semibold, design: .rounded)).tracking(-0.7)
                    Text(model.subtitle).font(.system(size: 13)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                VStack(spacing: 0) {
                    status("gamecontroller", title: "Controller", value: model.controllerName ?? "Nicht verbunden", active: model.controllerName != nil)
                    Divider().opacity(0.5)
                    status("antenna.radiowaves.left.and.right", title: "MyWhoosh", value: model.connected ? (model.appName ?? "Verbunden") : "Noch nicht verbunden", active: model.connected)
                }
                HStack(spacing: 24) {
                    direction(.down, arrow: "arrow.left", key: model.reversed ? "Rechts" : "Links")
                    Rectangle().fill(.white.opacity(0.09)).frame(width: 1, height: 64)
                    direction(.up, arrow: "arrow.right", key: model.reversed ? "Links" : "Rechts")
                }.frame(maxWidth: .infinity).padding(.vertical, 8)
                VStack(spacing: 13) {
                    Toggle("Gedrückt halten: mehrere Gänge", isOn: $model.holdToRepeat).toggleStyle(.switch).controlSize(.small)
                    Toggle("Links und rechts tauschen", isOn: $model.reversed).toggleStyle(.switch).controlSize(.small)
                }.font(.system(size: 12))
                HStack {
                    Circle().fill(model.ready ? accent : .gray).frame(width: 5, height: 5)
                    Text(model.lastInput).lineLimit(2).font(.system(size: 11)).foregroundStyle(.secondary)
                    Spacer()
                    Text("\(model.commands)").font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                }.accessibilityElement(children: .combine)
                HStack {
                    Button(model.controllerName == nil ? "Bluetooth öffnen" : "MyWhoosh öffnen") {
                        if model.controllerName == nil { model.openBluetooth() } else { model.openMyWhoosh() }
                    }.buttonStyle(.borderedProminent).tint(accent).controlSize(.large)
                    Spacer()
                    Button { model.reconnect() } label: { Image(systemName: "arrow.clockwise") }.help("Erneut verbinden · ⌘R")
                    Button { showHelp.toggle() } label: { Image(systemName: "questionmark.circle") }.help("Einrichtung")
                }.buttonStyle(.borderless)
                if showHelp {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("1  Controller in macOS per Bluetooth verbinden.")
                        Text("2  Lokales Netzwerk für Shift erlauben.")
                        Text("3  In MyWhoosh „Shift“ als Controller auswählen und MyShift aktivieren.")
                        Text("Mac und Trainings-App müssen im selben lokalen Netzwerk sein. Shift sendet ausschließlich Controller-Befehle; es ersetzt keinen Smart-Trainer.")
                            .foregroundStyle(.secondary)
                    }.font(.system(size: 12)).transition(.opacity)
                }
                HStack {
                    Text("1.0.0 · Lokal. Ohne Konto.")
                    Spacer()
                    Link("Quellcode", destination: URL(string: "https://github.com/JoshuaForster02/Shift")!)
                }.font(.system(size: 10)).foregroundStyle(.tertiary)
            }.padding(.horizontal, 30).padding(.bottom, 24)
        }
        .background(Color(red: 0.065, green: 0.065, blue: 0.075))
        .tint(accent)
        .animation(.easeInOut(duration: 0.18), value: model.ready)
        .animation(.easeInOut(duration: 0.18), value: showHelp)
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
                Image(systemName: arrow).font(.system(size: 28, weight: .light))
                    .foregroundStyle(model.lastDirection == action ? accent : .white)
                Text(action == .up ? "Hoch" : "Runter").font(.system(size: 14, weight: .semibold))
                Text("Steuerkreuz \(key.lowercased())").font(.system(size: 10)).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity).contentShape(Rectangle())
        }.buttonStyle(.plain).disabled(!model.connected).help(action.title)
    }
}

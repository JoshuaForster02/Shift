import Foundation
import CoreBluetooth

struct ClickDevice: Identifiable {
    let id: UUID
    let name: String
    let status: String
    let connected: Bool
}

// All callbacks, timers and writes are confined to the main queue.
final class ClickBluetooth: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    var onChange: (() -> Void)?
    var onButtons: ((ClickButtons) -> Void)?
    private(set) var message = "Click V2 direkt in Shift verbinden."
    private(set) var scanning = false
    private var central: CBCentralManager?
    private var wantedScan = false
    private var scanTimer: Timer?
    private var powerTimer: Timer?
    private var found: [UUID: CBPeripheral] = [:]
    private var labels: [UUID: String] = [:]
    private var sessions: [UUID: Session] = [:]
    private var disconnecting: Set<UUID> = []
    private var buttons = ClickButtons.released
    private let service = CBUUID(string: "00000001-19ca-4651-86e5-fa29dcdd09d1")
    private let async = CBUUID(string: "00000002-19ca-4651-86e5-fa29dcdd09d1")
    private let rx = CBUUID(string: "00000003-19ca-4651-86e5-fa29dcdd09d1")
    private let tx = CBUUID(string: "00000004-19ca-4651-86e5-fa29dcdd09d1")
    private final class Session {
        let peripheral: CBPeripheral
        var status = "Verbindet …"
        var channels: [CBUUID: CBCharacteristic] = [:]
        var subscribed = Set<CBUUID>()
        var queue: [Data] = []
        var writing = false
        var active = false
        var acked = false
        var timer: Timer?
        var deadline: Timer?
        init(_ peripheral: CBPeripheral) { self.peripheral = peripheral }
        deinit { timer?.invalidate(); deadline?.invalidate() }
    }
    var devices: [ClickDevice] {
        found.values.map { p in
            ClickDevice(id: p.identifier, name: labels[p.identifier] ?? p.name ?? "Zwift Click V2",
                        status: sessions[p.identifier]?.status ?? "Gefunden", connected: sessions[p.identifier] != nil)
        }.sorted { $0.name == $1.name ? $0.id.uuidString < $1.id.uuidString : $0.name < $1.name }
    }
    var readyName: String? {
        sessions.values.contains(where: { $0.active }) ? "Zwift Click V2" : nil
    }
    func scan() {
        wantedScan = true
        if central == nil { central = CBCentralManager(delegate: self, queue: .main) }
        powerTimer?.invalidate()
        powerTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: false) { [weak self] _ in
            guard let self, self.wantedScan else { return }
            self.wantedScan = false; self.message = "macOS antwortet nicht. Bluetooth-Freigabe prüfen und erneut suchen."; self.onChange?()
        }
        if central?.state == .poweredOn { beginScan() }
        else if let central, [.unauthorized, .poweredOff, .unsupported].contains(central.state) { centralManagerDidUpdateState(central) }
    }
    private func beginScan() {
        wantedScan = false; powerTimer?.invalidate(); scanTimer?.invalidate()
        found = found.filter { sessions[$0.key] != nil }
        scanning = true; message = "Beide Click V2 aufwecken. Suche läuft …"
        central?.scanForPeripherals(withServices: nil)
        scanTimer = Timer.scheduledTimer(withTimeInterval: 8, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.central?.stopScan(); self.scanning = false
            self.message = self.found.isEmpty ? "Kein Click V2 gefunden. Controller wecken und Zwift schließen." : "Beide V2-Controller nacheinander verbinden."
            self.onChange?()
        }
        onChange?()
    }
    func connect(_ id: UUID) {
        guard sessions[id] == nil, let p = found[id] else { return }
        guard !disconnecting.contains(id) else { message = "Vorige Verbindung wird beendet. Bitte kurz erneut versuchen."; onChange?(); return }
        guard sessions.count < 2 else { message = "Es sind bereits zwei Controller verbunden."; onChange?(); return }
        let s = Session(p); sessions[id] = s; p.delegate = self
        s.deadline = Timer.scheduledTimer(withTimeInterval: 15, repeats: false) { [weak self, weak s] _ in
            guard let self, let s, self.sessions[id] === s else { return }
            self.disconnect(id); self.message = "Click antwortet nicht. Controller wecken und erneut verbinden."; self.onChange?()
        }
        central?.connect(p); onChange?()
    }
    func disconnect(_ id: UUID) {
        guard let s = sessions.removeValue(forKey: id) else { return }
        s.timer?.invalidate(); s.deadline?.invalidate()
        if s.peripheral.state != .disconnected {
            disconnecting.insert(id)
            central?.cancelPeripheralConnection(s.peripheral)
        }
        buttons = .released; onButtons?(.released); onChange?()
    }
    func stop() {
        wantedScan = false; scanning = false
        powerTimer?.invalidate(); scanTimer?.invalidate(); central?.stopScan()
        for id in Array(sessions.keys) { disconnect(id) }
    }
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn { if wantedScan { beginScan() }; return }
        for id in Array(sessions.keys) { disconnect(id) }
        if central.state == .unknown || central.state == .resetting { return }
        wantedScan = false; scanning = false; powerTimer?.invalidate(); scanTimer?.invalidate()
        message = central.state == .unauthorized ? "Bluetooth für Shift in Systemeinstellungen → Datenschutz & Sicherheit erlauben." : (central.state == .poweredOff ? "Bluetooth am Mac einschalten." : "Bluetooth LE ist nicht verfügbar.")
        onChange?()
    }
    func centralManager(_ central: CBCentralManager, didDiscover p: CBPeripheral, advertisementData a: [String: Any], rssi: NSNumber) {
        let name = a[CBAdvertisementDataLocalNameKey] as? String ?? p.name ?? ""
        let manufacturer = Array(a[CBAdvertisementDataManufacturerDataKey] as? Data ?? Data())
        let pod = manufacturer.count >= 3 && manufacturer[0] == 0x4a && manufacturer[1] == 0x09 ? manufacturer[2] : 0
        guard pod == 0x0a || pod == 0x0b || name.lowercased().contains("zwift click") else { return }
        found[p.identifier] = p
        labels[p.identifier] = pod == 0x0a ? "Click V2 rechts (+)" : (pod == 0x0b ? "Click V2 links (−)" : name)
        onChange?()
    }
    func centralManager(_ central: CBCentralManager, didConnect p: CBPeripheral) {
        guard sessions[p.identifier] != nil else { central.cancelPeripheralConnection(p); return }
        p.discoverServices([service])
    }
    func centralManager(_ central: CBCentralManager, didFailToConnect p: CBPeripheral, error: Error?) {
        disconnecting.remove(p.identifier); disconnect(p.identifier)
    }
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral p: CBPeripheral, error: Error?) {
        disconnecting.remove(p.identifier); disconnect(p.identifier)
    }
    func peripheral(_ p: CBPeripheral, didDiscoverServices error: Error?) {
        guard sessions[p.identifier] != nil else { return }
        guard error == nil, let srv = p.services?.first(where: { $0.uuid == service }) else { disconnect(p.identifier); return }
        p.discoverCharacteristics([async, rx, tx], for: srv)
    }
    func peripheral(_ p: CBPeripheral, didDiscoverCharacteristicsFor srv: CBService, error: Error?) {
        guard let s = sessions[p.identifier] else { return }
        guard error == nil else { disconnect(p.identifier); return }
        for c in srv.characteristics ?? [] { s.channels[c.uuid] = c }
        guard let a = s.channels[async], let t = s.channels[tx], let r = s.channels[rx], r.properties.contains(.write) || r.properties.contains(.writeWithoutResponse) else { disconnect(p.identifier); return }
        p.setNotifyValue(true, for: a); p.setNotifyValue(true, for: t)
    }
    func peripheral(_ p: CBPeripheral, didUpdateNotificationStateFor c: CBCharacteristic, error: Error?) {
        guard let s = sessions[p.identifier] else { return }
        guard error == nil, c.isNotifying else { disconnect(p.identifier); return }
        s.subscribed.insert(c.uuid)
        guard s.subscribed.contains(async), s.subscribed.contains(tx), s.timer == nil else { return }
        s.deadline?.invalidate(); s.status = "Taste zum Prüfen drücken"
        for (i, data) in ClickProtocol.activation.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.1) { [weak self, weak s] in
                guard let self, let s, self.sessions[p.identifier] === s else { return }
                self.enqueue(data, s)
            }
        }
        s.timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self, weak s] _ in
            guard let self, let s, self.sessions[p.identifier] === s else { return }
            self.enqueue(ClickProtocol.rideOn, s)
        }
        onChange?()
    }
    private func enqueue(_ data: Data, _ s: Session) {
        guard s.queue.count < 8 else { disconnect(s.peripheral.identifier); return }
        s.queue.append(data); drain(s)
    }
    private func drain(_ s: Session) {
        guard !s.writing, !s.queue.isEmpty, let c = s.channels[rx] else { return }
        if c.properties.contains(.write) {
            s.writing = true
            s.peripheral.writeValue(s.queue.removeFirst(), for: c, type: .withResponse)
            s.deadline?.invalidate()
            s.deadline = Timer.scheduledTimer(withTimeInterval: 5, repeats: false) { [weak self, weak s] _ in
                guard let self, let s, self.sessions[s.peripheral.identifier] === s else { return }
                self.disconnect(s.peripheral.identifier)
            }
        } else if s.peripheral.canSendWriteWithoutResponse {
            s.peripheral.writeValue(s.queue.removeFirst(), for: c, type: .withoutResponse)
            drain(s)
        }
    }
    func peripheralIsReady(toSendWriteWithoutResponse p: CBPeripheral) { if let s = sessions[p.identifier] { drain(s) } }
    func peripheral(_ p: CBPeripheral, didWriteValueFor c: CBCharacteristic, error: Error?) {
        guard let s = sessions[p.identifier], c.uuid == rx else { return }
        s.deadline?.invalidate(); s.writing = false
        if error != nil { disconnect(p.identifier) } else { drain(s) }
    }
    func peripheral(_ p: CBPeripheral, didUpdateValueFor c: CBCharacteristic, error: Error?) {
        guard let s = sessions[p.identifier], c.uuid == async || c.uuid == tx, error == nil, let data = c.value else { return }
        if ClickProtocol.needsActivation(data) {
            s.status = "Zwift-Aktivierung prüfen"; s.active = false
            buttons = .released; onButtons?(.released)
            if !s.acked { s.acked = true; enqueue(ClickProtocol.acknowledgement, s) }
            onChange?(); return
        }
        guard let next = ClickButtons.decode(data) else { return }
        if !s.active { s.active = true; s.status = "Tasten kommen an"; onChange?() }
        // Both V2 pods can mirror the entire pair bitmap. Share state.
        if next != buttons { buttons = next; onButtons?(next) }
    }
}

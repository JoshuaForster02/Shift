import Foundation
import CoreBluetooth

// Independent implementation of OpenBikeControl/BLE.md (MIT).
// This advertises an OpenBikeControl controller, not a Zwift/FTMS device.
final class BluetoothOutput: NSObject, CBPeripheralManagerDelegate {
    var onChange: (() -> Void)?
    var onDelivery: ((ShiftAction) -> Void)?
    private(set) var message = "Bluetooth-Ausgabe ist aus"
    private(set) var appName: String?
    private var manager: CBPeripheralManager?
    private var enabled = false
    private var buttonCharacteristic: CBMutableCharacteristic?
    private var subscribers: [UUID: CBCentral] = [:]
    private var parsers: [UUID: PeerParser] = [:]
    private var capabilities: [UUID: PeerInfo] = [:]
    private var queue: [(ShiftAction, Bool)] = []
    private var up = false
    private var down = false
    private let serviceID = CBUUID(string: "d273f680-d548-419d-b9d1-fa0472345229")
    private let buttonID = CBUUID(string: "d273f681-d548-419d-b9d1-fa0472345229")
    private let hapticID = CBUUID(string: "d273f682-d548-419d-b9d1-fa0472345229")
    private let infoID = CBUUID(string: "d273f683-d548-419d-b9d1-fa0472345229")
    var connected: Bool {
        enabled && !subscribers.isEmpty && subscribers.keys.allSatisfy { id in
            guard let info = capabilities[id] else { return true }
            return info.supports(.up) && info.supports(.down)
        }
    }
    func start() {
        guard !enabled else { return }
        enabled = true
        if manager == nil { manager = CBPeripheralManager(delegate: self, queue: .main) }
        else if let manager { peripheralManagerDidUpdateState(manager) }
    }
    func stop() {
        enabled = false; manager?.stopAdvertising(); manager?.removeAllServices()
        queue.removeAll(); subscribers.removeAll(); parsers.removeAll(); capabilities.removeAll()
        up = false; down = false; appName = nil; buttonCharacteristic = nil
        message = "Bluetooth-Ausgabe ist aus"; onChange?()
    }
    func shift(_ action: ShiftAction, pressed: Bool) {
        guard connected else { return }
        if action == .up { guard up != pressed else { return }; up = pressed }
        else { guard down != pressed else { return }; down = pressed }
        guard queue.count < 64 else { stop(); message = "Bluetooth-Ausgabe überlastet. Bitte neu auswählen."; onChange?(); return }
        queue.append((action, pressed)); flush()
    }
    private func flush() {
        guard let manager, let c = buttonCharacteristic, connected else { return }
        while let next = queue.first {
            guard manager.updateValue(next.0.packet(pressed: next.1), for: c, onSubscribedCentrals: Array(subscribers.values)) else { return }
            queue.removeFirst(); if next.1 { onDelivery?(next.0) }
        }
    }
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        guard enabled else { return }
        guard peripheral.state == .poweredOn else {
            subscribers.removeAll(); queue.removeAll(); capabilities.removeAll(); parsers.removeAll()
            up = false; down = false
            message = peripheral.state == .unauthorized ? "Bluetooth für Shift erlauben" : "Bluetooth ist nicht bereit"
            onChange?(); return
        }
        peripheral.stopAdvertising(); peripheral.removeAllServices()
        let buttons = CBMutableCharacteristic(type: buttonID, properties: [.read, .notify], value: nil, permissions: [.readable])
        let haptic = CBMutableCharacteristic(type: hapticID, properties: [.write, .writeWithoutResponse], value: nil, permissions: [.writeable])
        let info = CBMutableCharacteristic(type: infoID, properties: [.write, .writeWithoutResponse], value: nil, permissions: [.writeable])
        let service = CBMutableService(type: serviceID, primary: true)
        service.characteristics = [buttons, haptic, info]; buttonCharacteristic = buttons
        message = "Bluetooth-Controller wird vorbereitet …"; peripheral.add(service); onChange?()
    }
    func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?) {
        guard enabled else { return }
        guard error == nil else { message = "Bluetooth-Dienst konnte nicht starten"; onChange?(); return }
        peripheral.startAdvertising([CBAdvertisementDataLocalNameKey: "Shift", CBAdvertisementDataServiceUUIDsKey: [serviceID]])
    }
    func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: Error?) {
        guard enabled else { return }
        message = error == nil ? "Shift als OpenBikeControl-Bluetooth-Controller auswählen" : "Bluetooth-Werbung konnte nicht starten"
        onChange?()
    }
    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didSubscribeTo characteristic: CBCharacteristic) {
        guard enabled, characteristic.uuid == buttonID else { return }
        guard subscribers.count < 4 || subscribers[central.identifier] != nil else { return }
        subscribers[central.identifier] = central; message = "Bluetooth-App verbunden"; onChange?()
        // Include both released states on subscription; never inherit a held key.
        if let c = buttonCharacteristic {
            _ = peripheral.updateValue(Data([1, 1, 0, 2, 0]), for: c, onSubscribedCentrals: [central])
        }
    }
    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didUnsubscribeFrom characteristic: CBCharacteristic) {
        subscribers.removeValue(forKey: central.identifier); parsers.removeValue(forKey: central.identifier)
        capabilities.removeValue(forKey: central.identifier)
        if subscribers.isEmpty { queue.removeAll(); up = false; down = false; appName = nil; message = "Bluetooth-App getrennt" }
        onChange?()
    }
    func peripheralManagerIsReady(toUpdateSubscribers peripheral: CBPeripheralManager) { flush() }
    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveRead request: CBATTRequest) {
        guard request.characteristic.uuid == buttonID else { peripheral.respond(to: request, withResult: .requestNotSupported); return }
        let value = Data([1, 1, up ? 1 : 0, 2, down ? 1 : 0])
        guard request.offset <= value.count else { peripheral.respond(to: request, withResult: .invalidOffset); return }
        request.value = value.subdata(in: request.offset..<value.count); peripheral.respond(to: request, withResult: .success)
    }
    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        guard let first = requests.first else { return }
        var result = CBATTError.Code.success
        for request in requests {
            guard let data = request.value, !data.isEmpty, data.count <= 512, request.offset == 0 else { result = .invalidAttributeValueLength; break }
            if request.characteristic.uuid == hapticID {
                if data.count != 4 || data.first != 3 { result = .invalidAttributeValueLength; break }
                // No haptic hardware: valid commands are acknowledged, as allowed by spec.
            } else if request.characteristic.uuid == infoID {
                let id = request.central.identifier
                guard parsers[id] != nil || parsers.count < 4 else { result = .insufficientResources; break }
                var parser = parsers[id] ?? PeerParser()
                do {
                    for info in try parser.feed(data) { capabilities[id] = info; appName = info.name }
                    parsers[id] = parser
                } catch { parsers.removeValue(forKey: id); result = .invalidPdu; break }
            } else { result = .requestNotSupported; break }
        }
        peripheral.respond(to: first, withResult: result); onChange?()
    }
}

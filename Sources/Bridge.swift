import Foundation
import Network

final class DeviceBridge: NSObject, NetServiceDelegate {
    struct Peer {
        let connection: NWConnection
        var parser = PeerParser()
        var info: PeerInfo?
    }
    var onChange: () -> Void = {}
    var onDelivery: (ShiftAction) -> Void = { _ in }
    private(set) var peers: [UUID: Peer] = [:]
    private(set) var message = "Verbindung wird vorbereitet …"
    private(set) var listening = false
    private var listener: NWListener?
    private var service: NetService?
    private var heartbeat: Timer?
    private var generation = 0
    private let deviceID: String

    override init() {
        let key = "deviceID"
        deviceID = UserDefaults.standard.string(forKey: key) ?? UUID().uuidString
        super.init()
        UserDefaults.standard.set(deviceID, forKey: key)
    }

    var connectedName: String? { peers.values.compactMap(\.info?.name).sorted().first }
    var port: NWEndpoint.Port? { listener?.port }
    var connected: Bool { !peers.isEmpty }
    var canShift: Bool {
        peers.values.contains { $0.info == nil || ($0.info!.supports(.up) && $0.info!.supports(.down)) }
    }

    func start(advertiseService: Bool = true) {
        stop()
        let current = generation
        do {
            let parameters = NWParameters.tcp
            parameters.allowLocalEndpointReuse = true
            let server = try NWListener(using: parameters, on: .any)
            listener = server
            server.stateUpdateHandler = { [weak self, weak server] state in
                guard let self, current == self.generation else { return }
                switch state {
                case .ready:
                    guard let port = server?.port else { return }
                    if advertiseService { self.advertise(port: port) }
                    else { self.listening = true }
                case .waiting:
                    self.message = "Lokales Netzwerk prüfen und erneut verbinden."
                    self.listening = false
                case .failed:
                    self.message = "Netzwerk nicht verfügbar. Bitte erneut versuchen."
                    self.listening = false
                default: break
                }
                self.onChange()
            }
            server.newConnectionHandler = { [weak self] connection in
                guard let self, current == self.generation else { connection.cancel(); return }
                self.accept(connection)
            }
            server.start(queue: .main)
            heartbeat = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
                self?.broadcast(Data([0x02, 0xFF, 0x01]))
            }
        } catch {
            message = "Netzwerk konnte nicht gestartet werden."
            onChange()
        }
    }

    private func advertise(port: NWEndpoint.Port) {
        let service = NetService(domain: "local.", type: "_openbikecontrol._tcp.", name: "Shift", port: Int32(port.rawValue))
        service.delegate = self
        let fields = ["version": "1", "id": deviceID, "name": "Shift", "manufacturer": "Shift",
                      "model": "Mac Controller", "service-uuids": "d273f680-d548-419d-b9d1-fa0472345229"]
        service.setTXTRecord(NetService.data(fromTXTRecord: fields.mapValues { Data($0.utf8) }))
        self.service = service
        service.publish()
    }

    func netServiceDidPublish(_ sender: NetService) {
        listening = true
        message = "In MyWhoosh als Controller „Shift“ auswählen."
        onChange()
    }

    func netService(_ sender: NetService, didNotPublish errorDict: [String: NSNumber]) {
        listening = false
        message = "Lokales Netzwerk in den Systemeinstellungen erlauben."
        onChange()
    }

    private func accept(_ connection: NWConnection) {
        guard peers.count < 4 else { connection.cancel(); return }
        let id = UUID()
        peers[id] = Peer(connection: connection)
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard let self, let connection, self.peers[id] != nil else { return }
            switch state {
            case .ready:
                self.send(Data([0x02, 0xFF, 0x01]), to: connection)
                self.receive(id)
            case .failed, .cancelled:
                self.peers.removeValue(forKey: id)
                connection.cancel()
            default: break
            }
            self.onChange()
        }
        connection.start(queue: .main)
        onChange()
    }

    private func receive(_ id: UUID) {
        guard let peer = peers[id] else { return }
        peer.connection.receive(minimumIncompleteLength: 1, maximumLength: 1024) { [weak self] data, _, done, error in
            guard let self, var peer = self.peers[id] else { return }
            if let data, !data.isEmpty {
                do {
                    for info in try peer.parser.feed(data) { peer.info = info }
                    self.peers[id] = peer
                    self.onChange()
                } catch {
                    peer.connection.cancel()
                    self.peers.removeValue(forKey: id)
                    self.onChange()
                    return
                }
            }
            if done || error != nil {
                peer.connection.cancel()
                self.peers.removeValue(forKey: id)
                self.onChange()
            } else { self.receive(id) }
        }
    }

    func shift(_ action: ShiftAction, pressed: Bool) {
        var sent = false
        for peer in peers.values where peer.info?.supports(action) != false {
            guard case .ready = peer.connection.state else { continue }
            send(action.packet(pressed: pressed), to: peer.connection)
            sent = true
        }
        if sent && pressed { onDelivery(action) }
    }

    private func send(_ data: Data, to connection: NWConnection) {
        connection.send(content: data, completion: .contentProcessed { error in
            if error != nil { connection.cancel() }
        })
    }
    private func broadcast(_ data: Data) { peers.values.forEach { send(data, to: $0.connection) } }

    func stop() {
        generation += 1
        heartbeat?.invalidate()
        heartbeat = nil
        service?.stop()
        service = nil
        listener?.cancel()
        listener = nil
        let oldPeers = peers.values.map(\.connection)
        peers.removeAll()
        oldPeers.forEach { $0.cancel() }
        listening = false
    }
}

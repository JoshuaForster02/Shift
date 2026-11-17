import Foundation
import Network

@main struct BridgeTests {
    static func main() { TCPProbe().run() }
}

final class TCPProbe {
    let bridge = DeviceBridge()
    var client: NWConnection?
    var received = Data()
    var completed = false
    var sent = false

    func receive(_ connection: NWConnection) {
            connection.receive(minimumIncompleteLength: 1, maximumLength: 128) { [self] data, _, _, error in
                precondition(error == nil, "Loopback receive failed")
                if let data { received += data }
                if received.count >= 6 {
                    precondition(Array(received.prefix(3)) == [2, 255, 1], "Initial device status")
                    precondition(Array(received.dropFirst(3).prefix(3)) == [1, 1, 1], "Shift packet over real TCP")
                    completed = true
                } else { receive(connection) }
            }
    }

    func run() {
        bridge.onChange = { [self] in
            if bridge.listening, client == nil, let port = bridge.port {
                let connection = NWConnection(host: "127.0.0.1", port: port, using: .tcp)
                client = connection
                connection.stateUpdateHandler = { state in
                    if case .ready = state {
                        let name = Array("mywhoosh".utf8)
                        let frame = Data([4, 1, UInt8(name.count)] + name + [1, 49, 2, 1, 2])
                        connection.send(content: frame + Data([0]) + frame, completion: .contentProcessed { error in precondition(error == nil) })
                        self.receive(connection)
                    }
                }
                connection.start(queue: .main)
            }
            if bridge.connectedName == "mywhoosh", !sent {
                precondition(bridge.canShift)
                sent = true
                bridge.shift(.up, pressed: true)
            }
        }
        bridge.start(advertiseService: false)
        let deadline = Date().addingTimeInterval(8)
        while !completed && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
        precondition(completed, "TCP integration timed out")
        bridge.onChange = {}
        client?.cancel()
        bridge.stop()
        print("TCP integration passed: MyWhoosh NUL padding, app identity, capabilities, status and shift delivery")
    }
}

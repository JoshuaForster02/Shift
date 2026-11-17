import Foundation
import Network
import Combine
import dnssd
import Darwin

// Only advertises a separate, explicitly named test device. Never connects to real hardware.
final class VirtualTrainerServer: ObservableObject {
    static let shared = VirtualTrainerServer()
    @Published var watts=150.0
    @Published var cadence=85.0
    @Published var speed=35.0
    @Published var heartRate=110.0
    @Published var followErg=false
    @Published var signal=true
    @Published private(set) var running=false
    @Published private(set) var clients=0
    @Published private(set) var status="Ausgeschaltet"
    @Published private(set) var command="Noch kein Steuerbefehl"
    @Published private(set) var actualWatts=150.0
    private var listener: NWListener?, timer: Timer?
    private var dnsConnection: DNSServiceRef?, dnsService: DNSServiceRef?, dnsRecord: DNSRecordRef?
    private var generation=0, engine=TrainerProtocol()
    private struct Peer { let connection:NWConnection; var state=TrainerClient(); var pending=0 }
    private var peers:[UUID:Peer]=[:]
    var deviceName:String { "Shift-Trainer-" + String((UserDefaults.standard.string(forKey:"deviceID") ?? "TEST01").replacingOccurrences(of:"-",with:"").prefix(6)).lowercased() }
    private var advertisedMAC:String {
        let hex=(UserDefaults.standard.string(forKey:"deviceID") ?? "000053494d").lowercased().filter{$0.isHexDigit}
        let chars=Array(String(hex.prefix(10)).padding(toLength:10,withPad:"0",startingAt:0))
        return "02:" + stride(from:0,to:10,by:2).map{String(chars[$0...($0+1)])}.joined(separator:":")
    }
    var port:NWEndpoint.Port? {listener?.port}
    func start(announce:Bool=true) {
        stop();generation += 1;let current=generation
        do {
            let parameters=NWParameters.tcp
            parameters.allowLocalEndpointReuse=true
            if let ip=parameters.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options { ip.version = .v4 }
            if !announce { parameters.requiredLocalEndpoint = .hostPort(host:"127.0.0.1",port:.any) }
            let server: NWListener
            if announce { server=try NWListener(using:parameters,on:36866) }
            else { server=try NWListener(using:parameters) }
            listener=server;status="LAN-Trainer startet …"
            server.stateUpdateHandler={ [weak self,weak server] state in
                guard let self,current==self.generation else{return}
                switch state {
                case .ready:
                    guard let port=server?.port else{return}
                    do { if announce { try self.advertise(port.rawValue) };self.running=true;self.status="In MyWhoosh über LAN als \(self.deviceName) auswählen.";self.beginTimer() }
                    catch {self.stop();self.status="Ankündigung nicht möglich: \(error.localizedDescription)"}
                case .failed(let error): self.stop();self.status="LAN-Port 36866 nicht verfügbar: \(error.localizedDescription)"
                case .waiting(let error): self.status="Netzwerk wartet: \(error.localizedDescription)"
                default:break
                }
            }
            server.newConnectionHandler={ [weak self] connection in
                guard let self,current==self.generation,self.peers.count<4 else{connection.cancel();return}
                self.accept(connection)
            }
            server.start(queue:.main)
        }catch{status="Trainer konnte nicht starten: \(error.localizedDescription)"}
    }
    func stop() {
        generation += 1;timer?.invalidate();timer=nil
        if let dnsService {DNSServiceRefDeallocate(dnsService)};dnsService=nil
        if let dnsConnection {DNSServiceRefDeallocate(dnsConnection)};dnsConnection=nil;dnsRecord=nil
        listener?.cancel();listener=nil
        let connections=peers.values.map(\.connection);peers.removeAll();connections.forEach{$0.cancel()}
        running=false;clients=0;status="Ausgeschaltet";engine=TrainerProtocol();command=engine.lastCommand
    }
    private func advertise(_ port:UInt16)throws {
        guard let address=Self.localAddress() else{throw NSError(domain:"ShiftTrainer",code:1,userInfo:[NSLocalizedDescriptionKey:"Kein aktives lokales IPv4-Netz. WLAN oder Ethernet verbinden."])}
        let host=deviceName.lowercased()+".local."
        var connection:DNSServiceRef?
        guard DNSServiceCreateConnection(&connection)==0,let connection else{throw NSError(domain:"DNS",code:1)}
        dnsConnection=connection
        var ipv4=in_addr();inet_pton(AF_INET,address.1,&ipv4)
        let recordResult=withUnsafePointer(to:&ipv4){ptr in DNSServiceRegisterRecord(connection,&dnsRecord,DNSServiceFlags(kDNSServiceFlagsUnique),address.0,host,UInt16(kDNSServiceType_A),UInt16(kDNSServiceClass_IN),4,UnsafeRawPointer(ptr),120,{_,_,_,error,context in
            guard error != 0,let context else{return}
            let model=Unmanaged<VirtualTrainerServer>.fromOpaque(context).takeUnretainedValue()
            model.stop();model.status="LAN-Adresse konnte nicht angekündigt werden (\(error))."
        },Unmanaged.passUnretained(self).toOpaque())}
        guard recordResult==0 else{throw NSError(domain:"DNS",code:Int(recordResult))}
        DNSServiceSetDispatchQueue(connection,.main)
        let fields=["ble-service-uuids":"1826,1818,180d","serial-number":"SIMULATION-001","mac-address":advertisedMAC]
        let txt=NetService.data(fromTXTRecord:fields.mapValues{Data($0.utf8)})
        let result=txt.withUnsafeBytes{bytes in DNSServiceRegister(&dnsService,0,address.0,deviceName,"_wahoo-fitness-tnp._tcp","local.",host,port.bigEndian,UInt16(txt.count),bytes.baseAddress,{_,_,error,_,_,_,context in
            guard error != 0,let context else{return}
            let model=Unmanaged<VirtualTrainerServer>.fromOpaque(context).takeUnretainedValue()
            model.stop();model.status="LAN-Dienst konnte nicht angekündigt werden (\(error))."
        },Unmanaged.passUnretained(self).toOpaque())}
        guard result==0,let dnsService else{throw NSError(domain:"DNS",code:Int(result))}
        DNSServiceSetDispatchQueue(dnsService,.main)
    }
    private static func localAddress()->(UInt32,String)? {
        var first:UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&first)==0,let first else{return nil};defer{freeifaddrs(first)}
        var current:UnsafeMutablePointer<ifaddrs>?=first, candidates:[(String,String)]=[]
        while let entry=current {
            defer{current=entry.pointee.ifa_next}
            let a=entry.pointee
            guard let addr=a.ifa_addr,addr.pointee.sa_family==UInt8(AF_INET),a.ifa_flags & UInt32(IFF_UP) != 0,a.ifa_flags & UInt32(IFF_LOOPBACK)==0 else{continue}
            let name=String(cString:a.ifa_name)
            guard name.hasPrefix("en")||name.hasPrefix("bridge") else{continue}
            var buffer=[CChar](repeating:0,count:Int(NI_MAXHOST))
            if getnameinfo(addr,socklen_t(addr.pointee.sa_len),&buffer,socklen_t(buffer.count),nil,0,NI_NUMERICHOST)==0 {
                let ip=String(cString:buffer);if !ip.hasPrefix("169.254."){candidates.append((name,ip))}
            }
        }
        guard let chosen=candidates.sorted(by:{$0.0<$1.0}).first else{return nil}
        return(if_nametoindex(chosen.0),chosen.1)
    }
    private func accept(_ connection:NWConnection) {
        let id=UUID();peers[id]=Peer(connection:connection)
        connection.stateUpdateHandler={ [weak self] state in
            guard let self,self.peers[id] != nil else{return}
            switch state {
            case .ready:self.clients=self.peers.count;self.status="MyWhoosh / Trainer-App verbunden";self.receive(id)
            case .failed,.cancelled:self.removePeer(id)
            default:break
            }
        };connection.start(queue:.main)
    }
    private func receive(_ id:UUID) {
        guard let peer=peers[id] else{return}
        peer.connection.receive(minimumIncompleteLength:1,maximumLength:4096){[weak self] data,_,done,error in
            guard let self,var peer=self.peers[id] else{return}
            if let data,!data.isEmpty {
                do {
                    for frame in try peer.state.parser.feed(data) {
                        for reply in self.engine.handle(frame,client:&peer.state){self.send(reply.encoded,to:peer.connection)}
                    }
                    if var current=self.peers[id]{current.state=peer.state;self.peers[id]=current};self.command=self.engine.lastCommand
                }catch{self.removePeer(id);return}
            }
            if done||error != nil{self.removePeer(id)}
            else{self.receive(id)}
        }
    }
    private func beginTimer(){
        timer?.invalidate()
        timer=Timer.scheduledTimer(withTimeInterval:0.2,repeats:true){[weak self]_ in
            guard let self,self.running else{return}
            self.engine.telemetry.watts=self.watts;self.engine.telemetry.cadence=self.cadence
            self.engine.telemetry.speed=self.speed;self.engine.telemetry.heartRate=self.heartRate
            self.engine.telemetry.followErg=self.followErg;self.engine.telemetry.signal=self.signal
            self.engine.telemetry.step(0.2);self.actualWatts=self.engine.telemetry.actualWatts
            for peer in self.peers.values {
                for uuid in peer.state.subscriptions where [0x2ad2,0x2a63,0x2a37].contains(uuid) {
                    if let value=self.engine.value(uuid){self.send(TrainerFrame(type:6,body:trainerUUID(uuid)+value).encoded,to:peer.connection)}
                }
            }
        }
        if let timer {RunLoop.main.add(timer,forMode:.common)}
    }
    private func removePeer(_ id:UUID){
        let peer=peers.removeValue(forKey:id);peer?.connection.cancel();clients=peers.count
        if clients==0 {engine.telemetry.targetWatts=nil;if running{status="Wartet auf MyWhoosh · \(deviceName)"}}
    }
    private func send(_ data:Data,to connection:NWConnection){
        guard let id=peers.first(where:{$0.value.connection === connection})?.key,var peer=peers[id] else{return}
        guard peer.pending<64 else{removePeer(id);return}
        peer.pending += 1;peers[id]=peer
        connection.send(content:data,completion:.contentProcessed{[weak self] error in
            guard let self,var peer=self.peers[id] else{return}
            if error != nil{self.removePeer(id);return}
            peer.pending=max(0,peer.pending-1);self.peers[id]=peer
        })
    }
}

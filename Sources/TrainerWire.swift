import Foundation

// Independent implementation of the documented Direct Connect wire format.
// Transport UUIDs are 16 bytes in network order; characteristic values use BLE little endian.
struct TrainerFrame: Equatable {
    var type: UInt8
    var sequence: UInt8 = 0
    var code: UInt8 = 0
    var body = Data()
    var encoded: Data { Data([1,type,sequence,code,UInt8(body.count >> 8),UInt8(body.count & 255)]) + body }
}
struct TrainerFrameParser {
    private var buffer = Data()
    mutating func feed(_ data: Data) throws -> [TrainerFrame] {
        guard buffer.count + data.count <= 16384 else { throw Failure.oversized }
        buffer.append(data)
        var result: [TrainerFrame] = []
        while buffer.count >= 6 {
            let bytes = Array(buffer.prefix(6))
            guard bytes[0] == 1 else { throw Failure.version }
            let length = Int(bytes[4]) * 256 + Int(bytes[5])
            guard length <= 4096 else { throw Failure.oversized }
            guard buffer.count >= 6 + length else { break }
            result.append(TrainerFrame(type:bytes[1],sequence:bytes[2],code:bytes[3],body:Data(buffer.dropFirst(6).prefix(length))))
            buffer = Data(buffer.dropFirst(6 + length))
        }
        return result
    }
    enum Failure: Error { case oversized, version }
}
func trainerUUID(_ short: UInt16) -> Data {
    Data([0,0,UInt8(short >> 8),UInt8(short & 255),0,0,0x10,0,0x80,0,0,0x80,0x5f,0x9b,0x34,0xfb])
}
func trainerShortUUID(_ value: Data) -> UInt16? {
    guard value.count == 16 else { return nil }
    let b=Array(value), short=UInt16(b[2])*256+UInt16(b[3])
    return value == trainerUUID(short) ? short : nil
}
func trainerLE(_ value: UInt16) -> Data { Data([UInt8(value & 255),UInt8(value >> 8)]) }
func trainerLE32(_ value: UInt32) -> Data { Data((0..<4).map { UInt8((value >> ($0 * 8)) & 255) }) }
func trainerBound(_ value: Double, _ maxValue: Double) -> Double { value.isFinite ? min(maxValue,max(0,value)) : 0 }
struct TrainerTelemetry {
    var watts = 150.0, cadence = 85.0, speed = 35.0, heartRate = 110.0
    var followErg = false, signal = true
    var targetWatts: Double?, grade = 0.0, resistance = 0.0
    private(set) var elapsed = 0.0, crankPhase = 0.0
    private(set) var revolutions: UInt16 = 0, crankTime: UInt16 = 0
    var actualWatts: Double { signal && cadence > 0 ? trainerBound(followErg ? (targetWatts ?? watts) : watts,30000) : 0 }
    mutating func step(_ dt: Double) {
        let dt = trainerBound(dt,1); elapsed += dt
        if signal && cadence > 0 {
            crankPhase += trainerBound(cadence,300) * dt / 60
            while crankPhase >= 1 {
                crankPhase -= 1; revolutions &+= 1
                let eventTime = elapsed - crankPhase * 60 / max(1,trainerBound(cadence,300))
                crankTime = UInt16(truncatingIfNeeded: Int(max(0,eventTime) * 1024))
            }
        }
    }
    var bikeData: Data {
        trainerLE(0x0244) + trainerLE(UInt16((signal ? trainerBound(speed,655.35) : 0) * 100)) + trainerLE(UInt16((signal ? trainerBound(cadence,300) : 0) * 2)) + trainerLE(UInt16(actualWatts)) + Data([UInt8(signal ? trainerBound(heartRate,240) : 0)])
    }
    var powerData: Data { trainerLE(0x0020) + trainerLE(UInt16(actualWatts)) + trainerLE(revolutions) + trainerLE(crankTime) }
    var hrData: Data { Data([0,UInt8(signal ? trainerBound(heartRate,240) : 0)]) }
}
struct TrainerClient {
    var parser = TrainerFrameParser()
    var subscriptions: Set<UInt16> = []
    var control = false
}
struct TrainerProtocol {
    // Direct Connect properties are READ=1, WRITE=2, NOTIFY=4 (not GATT bit values).
    static let services: [(UInt16,[(UInt16,UInt8)])] = [
        (0x1826,[(0x2acc,1),(0x2ad2,5),(0x2ad9,6),(0x2ada,4),(0x2ad3,5),(0x2ad4,1),(0x2ad5,1),(0x2ad6,1),(0x2ad8,1)]),
        (0x1818,[(0x2a63,5),(0x2a65,1),(0x2a5d,1)]),
        (0x180d,[(0x2a37,5),(0x2a38,1)]),
        (0x180a,[(0x2a29,1),(0x2a24,1),(0x2a25,1),(0x2a26,1)]),
        (0x1800,[(0x2a00,1)])
    ]
    var telemetry = TrainerTelemetry()
    var lastCommand = "Noch kein Steuerbefehl"
    func value(_ uuid: UInt16) -> Data? {
        switch uuid {
        case 0x2acc: return trainerLE32(0x00004082) + trainerLE32(0x0000200e)
        case 0x2ad2: return telemetry.bikeData
        case 0x2a63: return telemetry.powerData
        case 0x2a65: return trainerLE32(0x08)
        case 0x2a5d,0x2a38: return Data([13])
        case 0x2a37: return telemetry.hrData
        case 0x2ad3: return Data([0,2])
        case 0x2ad4: return trainerLE(0)+trainerLE(65535)+trainerLE(1)
        case 0x2ad5: return trainerLE(UInt16(bitPattern:-200))+trainerLE(200)+trainerLE(1)
        case 0x2ad6: return trainerLE(0)+trainerLE(1000)+trainerLE(1)
        case 0x2ad8: return trainerLE(0)+trainerLE(30000)+trainerLE(1)
        case 0x2a29: return Data("Shift".utf8)
        case 0x2a24: return Data("Virtual Test Trainer".utf8)
        case 0x2a25: return Data("SIMULATION-001".utf8)
        case 0x2a26: return Data("1.5.0".utf8)
        case 0x2a00: return Data("Shift Test Trainer".utf8)
        default: return nil
        }
    }
    mutating func handle(_ request: TrainerFrame, client: inout TrainerClient) -> [TrainerFrame] {
        func response(_ code: UInt8=0,_ body: Data=Data()) -> TrainerFrame { TrainerFrame(type:request.type,sequence:request.sequence,code:code,body:body) }
        let body = request.body
        if request.type == 1 {
            guard body.isEmpty else { return [response(2)] }
            return [response(0,Self.services.reduce(into:Data()) { $0 += trainerUUID($1.0) })]
        }
        guard body.count >= 16, let uuid = trainerShortUUID(Data(body.prefix(16))) else { return [response(4)] }
        let id=trainerUUID(uuid), payload=Data(body.dropFirst(16))
        switch request.type {
        case 2:
            guard payload.isEmpty, let service=Self.services.first(where:{$0.0==uuid}) else { return [response(3)] }
            return [response(0,service.1.reduce(into:id){$0 += trainerUUID($1.0)+Data([$1.1])})]
        case 3:
            guard payload.isEmpty, let value=value(uuid) else { return [response(4,id)] }
            return [response(0,id+value)]
        case 5:
            guard payload.count==1, payload.first! <= 1, let properties=Self.services.flatMap({$0.1}).first(where:{$0.0==uuid})?.1, properties & 4 != 0 else { return [response(5,id)] }
            if payload.first == 1 { client.subscriptions.insert(uuid) } else { client.subscriptions.remove(uuid) }
            var frames=[response(0,id)]
            if payload.first==1, let value=value(uuid) { frames.append(TrainerFrame(type:6,body:id+value)) }
            return frames
        case 4:
            guard uuid==0x2ad9, !payload.isEmpty else { return [response(5,id)] }
            let result=control(Array(payload),client:&client)
            var frames=[response(0,id)]
            if client.subscriptions.contains(uuid) { frames.append(TrainerFrame(type:6,body:id+Data([0x80,payload.first!,result]))) }
            return frames
        default: return [response(1)]
        }
    }
    private mutating func control(_ bytes: [UInt8], client: inout TrainerClient) -> UInt8 {
        let op=bytes[0]
        if op==0 { guard bytes.count==1 else{return 3};client.control=true;lastCommand="Steuerung angefordert";return 1 }
        guard client.control else { return 5 }
        func signed16(_ at:Int)->Int16 { Int16(bitPattern:UInt16(bytes[at])|UInt16(bytes[at+1])<<8) }
        switch op {
        case 1: guard bytes.count==1 else{return 3};telemetry.targetWatts=nil;telemetry.grade=0;telemetry.resistance=0;lastCommand="Zurücksetzen"
        case 2: guard bytes.count==3 else{return 3};telemetry.speed=Double(UInt16(bytes[1])|UInt16(bytes[2])<<8)/100;lastCommand="Tempo-Ziel"
        case 3: guard bytes.count==3 else{return 3};telemetry.grade=Double(signed16(1))/10;lastCommand="Steigungs-Ziel"
        case 4: guard bytes.count==3 else{return 3};telemetry.resistance=Double(signed16(1))/10;lastCommand="Widerstand: \(telemetry.resistance)"
        case 5: guard bytes.count==3, signed16(1)>=0 else{return 3};telemetry.targetWatts=Double(signed16(1));lastCommand="ERG-Ziel: \(Int(telemetry.targetWatts!)) W"
        case 7: guard bytes.count==1 else{return 3};lastCommand="Start"
        case 8: guard bytes.count==2, [1,2].contains(bytes[1]) else{return 3};lastCommand="Pause / Stopp"
        case 0x11: guard bytes.count==7 else{return 3};telemetry.grade=Double(signed16(3))/100;lastCommand=String(format:"Strecke: %.1f %%",telemetry.grade)
        default: return 2
        }
        return 1
    }
}

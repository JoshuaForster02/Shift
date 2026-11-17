import Foundation
@main struct TrainerTests {
 static func main() throws {
  var count=0
  func check(_ condition:Bool,_ name:String){precondition(condition,name);count+=1}
  let discover=TrainerFrame(type:1,sequence:42)
  check(Array(discover.encoded)==[1,1,42,0,0,0],"Wire header")
  var parser=TrainerFrameParser(), frames:[TrainerFrame]=[]
  for byte in discover.encoded {frames += try parser.feed(Data([byte]))}
  check(frames==[discover],"Fragmented stream")
  check(try parser.feed(discover.encoded+discover.encoded).count==2,"Coalesced frames")
  check(trainerShortUUID(trainerUUID(0x1826))==0x1826,"UUID network order")
  check(trainerShortUUID(Data(repeating:0,count:16))==nil,"Unknown UUID rejected")
  for invalid in [Data([2,1,0,0,0,0]),Data([1,1,0,0,0x20,0]),Data(repeating:1,count:16385)] {
   do{var p=TrainerFrameParser();_=try p.feed(invalid);preconditionFailure("Invalid frame accepted")}catch{count+=1}
  }
  var engine=TrainerProtocol(),client=TrainerClient()
  let services=engine.handle(discover,client:&client)
  check(services[0].sequence==42&&services[0].body.count==80,"Service discovery")
  let chars=engine.handle(TrainerFrame(type:2,body:trainerUUID(0x1818)),client:&client)[0]
  check(chars.body.count==67&&chars.body[32]==5,"CPS read/notify properties")
  check(engine.handle(TrainerFrame(type:2,body:trainerUUID(0xffff)),client:&client)[0].code==3,"Missing service")
  let controlID=trainerUUID(0x2ad9)
  _=engine.handle(TrainerFrame(type:5,body:controlID+Data([1])),client:&client)
  check(client.subscriptions.contains(0x2ad9),"Subscribe control point")
  var replies=engine.handle(TrainerFrame(type:4,body:controlID+Data([5,0xfa,0])),client:&client)
  check(replies.last!.body.suffix(3)==Data([0x80,5,5]),"Control requires ownership")
  replies=engine.handle(TrainerFrame(type:4,body:controlID+Data([0])),client:&client)
  check(client.control&&replies.last!.body.suffix(3)==Data([0x80,0,1]),"Request control")
  _=engine.handle(TrainerFrame(type:4,body:controlID+Data([5,0xfa,0])),client:&client)
  check(engine.telemetry.targetWatts==250,"ERG target decoded")
  engine.telemetry.followErg=true;check(engine.telemetry.actualWatts==250,"ERG follow")
  engine.telemetry.followErg=false;check(engine.telemetry.actualWatts==150,"Manual mode stays manual")
  replies=engine.handle(TrainerFrame(type:4,body:controlID+Data([5,1])),client:&client)
  check(replies.last!.body.suffix(3)==Data([0x80,5,3]),"Truncated control rejected")
  _=engine.handle(TrainerFrame(type:4,body:controlID+Data([0x11,0,0,0xf4,1,40,32])),client:&client)
  check(engine.telemetry.grade==5,"Course grade decoded")
  var t=TrainerTelemetry();t.cadence=120
  for _ in 0..<100{t.step(0.1)}
  check(t.revolutions==20,"CPS crank revolutions")
  check(t.powerData.count==8&&t.bikeData.count==9,"Telemetry packet lengths")
  t.watts=Double.infinity;t.speed=1e9;t.heartRate=1e9
  check(t.actualWatts==0&&Array(t.bikeData)[2]==255,"Finite and wire range limits")
  t.signal=false;check(t.actualWatts==0&&t.hrData==Data([0,0]),"Signal loss")
  _=engine.handle(TrainerFrame(type:5,body:controlID+Data([0])),client:&client)
  check(!client.subscriptions.contains(0x2ad9),"Unsubscribe")
  print("\(count) virtual trainer protocol and telemetry checks passed")
 }
}

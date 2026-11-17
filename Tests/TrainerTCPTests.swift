import Foundation
import Network
@main struct TrainerTCPTests {static func main(){TrainerTCPProbe().run()}}
final class TrainerTCPProbe {
 let server=VirtualTrainerServer.shared
 var client:NWConnection?,parser=TrainerFrameParser(),passed=false,replies=0
 func receive(_ connection:NWConnection){
  connection.receive(minimumIncompleteLength:1,maximumLength:4096){[self]data,_,_,error in
   precondition(error==nil)
   if let data{do{for frame in try parser.feed(data){
    replies+=1
    if frame.type==1{precondition(frame.sequence==21&&frame.body.count==80);connection.send(content:TrainerFrame(type:5,sequence:22,body:trainerUUID(0x2a63)+Data([1])).encoded,completion:.contentProcessed{_ in})}
    if frame.type==6&&frame.body.prefix(16)==trainerUUID(0x2a63){precondition(frame.body.count==24);passed=true}
   }}catch{preconditionFailure("Invalid trainer response")}}
   if !passed{receive(connection)}
  }
 }
 func run(){
  server.start(announce:false);let deadline=Date().addingTimeInterval(10)
  while Date()<deadline && !passed{
   if server.running&&client==nil,let port=server.port{
    let c=NWConnection(host:"127.0.0.1",port:port,using:.tcp);client=c
    c.stateUpdateHandler={ [self]state in if case .ready=state{c.send(content:TrainerFrame(type:1,sequence:21).encoded,completion:.contentProcessed{_ in});receive(c)}}
    c.start(queue:.main)
   }
   RunLoop.main.run(until:Date().addingTimeInterval(0.02))
  }
  let finalStatus=server.status;client?.cancel();server.stop();precondition(passed,"Trainer TCP integration timed out: \(finalStatus)")
  print("Trainer TCP integration passed: loopback service response and live CPS telemetry (\(replies) frames)")
 }
}

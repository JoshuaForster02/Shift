import SwiftUI

struct VirtualTrainerView: View {
    @ObservedObject private var trainer=VirtualTrainerServer.shared
    @Environment(\.dismiss) private var dismiss
    var body:some View {
        ScrollView {
            VStack(alignment:.leading,spacing:22){
                HStack{Text("Test-Trainer").font(.system(size:27,weight:.semibold,design:.rounded));Spacer();Button("Fertig"){dismiss()}}
                Text("Virtueller Rollentrainer für MyWhoosh auf diesem Mac. Der echte Trainer bleibt aus.").font(.system(size:13)).foregroundStyle(.secondary)
                HStack(alignment:.firstTextBaseline){Text(String(format:"%.0f",trainer.actualWatts)).font(.system(size:58,weight:.light,design:.rounded));Text("W").foregroundStyle(.secondary);Spacer();Label("SIMULATION",systemImage:"testtube.2").font(.system(size:10,design:.monospaced)).foregroundStyle(.blue)}
                Text(trainer.status).font(.system(size:12)).textSelection(.enabled)
                Text(trainer.deviceName).font(.system(size:11,design:.monospaced)).foregroundStyle(.secondary).textSelection(.enabled)
                HStack{Button(trainer.running ? "Trainer stoppen":"LAN-Trainer starten"){if trainer.running{trainer.stop()}else{trainer.start()}}.buttonStyle(.borderedProminent);Text("\(trainer.clients) Verbindung(en)").font(.system(size:11)).foregroundStyle(.secondary)}
                Divider()
                HStack{preset("Locker",150,85,35);preset("Sprint",1500,130,65);preset("Extrem",10000,160,200);Button("Stopp"){trainer.watts=0;trainer.cadence=0;trainer.speed=0;trainer.followErg=false}}
                instrument("Leistung",unit:"W",value:$trainer.watts,range:0...30000)
                instrument("Trittfrequenz",unit:"U/min",value:$trainer.cadence,range:0...300)
                instrument("Geschwindigkeit",unit:"km/h",value:$trainer.speed,range:0...655.35)
                instrument("Puls",unit:"bpm",value:$trainer.heartRate,range:0...240)
                Toggle("ERG-Ziel der Trainings-App folgen",isOn:$trainer.followErg).font(.system(size:12))
                Toggle("Simuliertes Signal aktiv",isOn:$trainer.signal).font(.system(size:12))
                Text(trainer.command).font(.system(size:12,design:.monospaced)).foregroundStyle(.secondary)
                DisclosureGroup("In MyWhoosh verwenden"){
                    Text("1. LAN-Trainer starten.\n2. In MyWhoosh Geräte öffnen und LAN einschalten.\n3. Den angezeigten Shift-Trainer als Leistung, Trittfrequenz und steuerbaren Trainer wählen. Shift als Controller zusätzlich gekoppelt lassen.\n\nMyWhoosh berechnet die Fahrgeschwindigkeit selbst aus Leistung und Strecke. Der km/h-Regler sendet den FTMS-Messwert; MyWhoosh muss diesen nicht als Fahrtempo übernehmen. Zum Schnelltesten Leistung erhöhen. In AEON World erlaubt Warp direkt bis zu 3.000 km/h.\n\nTestgerät nicht für echte Trainingsaufzeichnungen oder Wettbewerbe verwenden. Das Schließen dieses Fensters lässt den gestarteten Trainer weiterlaufen; mit „Trainer stoppen“ ausschalten.").font(.system(size:12)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true).padding(.top,8)
                }
            }.padding(28)
        }.frame(width:520,height:720).background(CircuitBackdrop(emphasis:0.3)).preferredColorScheme(.dark)
    }
    private func preset(_ name:String,_ watts:Double,_ cadence:Double,_ speed:Double)->some View{Button(name){trainer.watts=watts;trainer.cadence=cadence;trainer.speed=speed;trainer.signal=true;trainer.followErg=false}.font(.system(size:12))}
    private func instrument(_ name:String,unit:String,value:Binding<Double>,range:ClosedRange<Double>)->some View{
        VStack(alignment:.leading,spacing:8){
            HStack{Text(name).font(.system(size:12));Spacer();TextField(name,value:value,format:.number.precision(.fractionLength(0...1))).multilineTextAlignment(.trailing).textFieldStyle(.roundedBorder).frame(width:90).accessibilityLabel(name);Text(unit).font(.system(size:11)).foregroundStyle(.secondary).frame(width:44,alignment:.leading)}
            Slider(value:value,in:range).accessibilityLabel(name+" Regler")
        }
    }
}

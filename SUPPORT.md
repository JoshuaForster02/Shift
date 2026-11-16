# Shift 1.2 – Unterstützung

| Eingabe / Ausgabe | Stand |
|---|---|
| Shanwan, Xbox und macOS-Gamepads | GameController: Steuerkreuz, LB/RB, LT/RT, X/B, linker/rechter Stick |
| Zwift Click V1 | Direkt per BLE, unverschlüsseltes 0x37-Protokoll |
| Zwift Click V2 | Direkt per BLE, beide Pods, spiegelnde Pakete zusammengeführt; Zwift-Freigabe ggf. nötig |
| Tastatur-/HID-Fernbedienung, Anki-Remote im Tastaturmodus | Zwei anlernbare Tasten; Hintergrundzugriff braucht Bedienungshilfen |
| MyWhoosh | OpenBikeControl im lokalen Netzwerk, unabhängig von Vordergrund-App |
| Andere laufende Mac-Apps | Frei anlernbare Tastenausgabe an ausgewählte App, ausdrückliche Aktivierung und Bedienungshilfen nötig |
| Umkehren / Haltewiederholung / manuelles Schalten | Für alle Eingaben |
| Zwift Play/Ride, verschlüsselter Click V1 | Noch keine direkte Anbindung |
| Di2, SRAM AXS, Wahoo-Bike, CYCPLUS, Thinkrider, Elite, Wheeltop | Noch keine direkten Spezialprotokolle; vorhandener Tastatur-/Gamepad-Modus ggf. über die generischen Eingänge nutzbar |
| Reine Medien-/Lautstärketasten, ANT+, Maus-/Touch-Gesten | Noch nicht implementiert |
| Bluetooth-Geräteemulation / direkte FTMS-Trainersteuerung | Noch nicht implementiert |

Tastenausgabe erzeugt allein keine virtuelle Schaltung; die Ziel-App muss die gewählten Tastaturbefehle unterstützen. Keine vollständige BikeControl-Funktionsgleichheit. Es wurde kein App-Code aus der nichtkommerziell lizenzierten BikeControl-Version übernommen.

## Tests und Hardware
63 reine Protokoll-/Mapping-Prüfungen und echte TCP-Loopbackintegration. Universal-Build ARM64/Intel. Die V1-/V2-Verbindungswege und die unterschiedlichen Gamepad-Belegungen wurden noch nicht mit allen echten Geräten gefahren. HID-Hintergrundeingabe und Ausgabe benötigen eine vom Nutzer selbst erteilte macOS-Freigabe; die Freigabe wird nicht automatisch gesetzt.

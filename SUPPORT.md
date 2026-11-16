# Shift 1.3 – Unterstützung

| Eingabe / Ausgabe | Stand |
|---|---|
| Shanwan, Xbox und macOS-Gamepads | GameController: Steuerkreuz, LB/RB, LT/RT, X/B, linker/rechter Stick |
| Zwift Click V1 | Direkt per BLE, unverschlüsseltes 0x37-Protokoll |
| Zwift Click V2 | Direkt per BLE, beide Pods, spiegelnde Pakete zusammengeführt; Zwift-Freigabe ggf. nötig |
| Tastatur-/HID-Fernbedienung, Anki-Remote im Tastaturmodus | Zwei anlernbare Tasten; Hintergrundzugriff braucht Bedienungshilfen |
| MyWhoosh | OpenBikeControl im lokalen Netzwerk, unabhängig von Vordergrund-App |
| Andere laufende Mac-Apps | Frei anlernbare Tastenausgabe an ausgewählte App, ausdrückliche Aktivierung und Bedienungshilfen nötig |
| Umkehren / Haltewiederholung / manuelles Schalten | Für alle Eingaben |
| Zwift Ride (älteres unverschlüsseltes Protokoll) | Linker Controller bündelt beide Griffe; Gänge implementiert, Hardwaretest offen |
| Zwift Play, verschlüsselter Click V1 und Ride V2 | Noch keine direkte Anbindung |
| Di2, SRAM AXS, Wahoo-Bike, CYCPLUS, Thinkrider, Elite, Wheeltop | Noch keine direkten Spezialprotokolle; vorhandener Tastatur-/Gamepad-Modus ggf. über die generischen Eingänge nutzbar |
| Reine Medien-/Lautstärketasten, ANT+, Maus-/Touch-Gesten | Noch nicht implementiert |
| OpenBikeControl-Bluetooth-Ausgabe | Geräteemulation nach offenem BLE-Protokoll; reale Empfänger-App noch nicht geprüft |
| Zwift-Geräteemulation / direkte FTMS-Trainersteuerung | Noch nicht implementiert |

Tastenausgabe erzeugt allein keine virtuelle Schaltung; die Ziel-App muss die gewählten Tastaturbefehle unterstützen. Keine vollständige BikeControl-Funktionsgleichheit. Es wurde kein App-Code aus der nichtkommerziell lizenzierten BikeControl-Version übernommen.

## Tests und Hardware
95 reine Protokoll-/Mapping-/Setup-Prüfungen und echte TCP-Loopbackintegration. Universal-Build ARM64/Intel. Die V1-/V2-Verbindungswege und die unterschiedlichen Gamepad-Belegungen wurden noch nicht mit allen echten Geräten gefahren. HID-Hintergrundeingabe und Ausgabe benötigen eine vom Nutzer selbst erteilte macOS-Freigabe; die Freigabe wird nicht automatisch gesetzt.

## Einrichtung und Weitergabe
Einrichtungsassistent für MyWhoosh plus beide Click V2. Links/rechts-Verbindung wird getrennt geprüft, Plus/Minus als tatsächliche Eingaben geprüft. Bei mehreren möglichen Paaren erfolgt keine automatische Auswahl. Profile sind lokal, validiert und ohne Freigaben/Gerätekennungen exportierbar. Diagnoseexport enthält keine Konten, Geräte-IDs oder Trainingsdaten. Der Assistent bestätigt Eingabe und Verbindung, nicht das tatsächliche Schalten im laufenden Spiel.

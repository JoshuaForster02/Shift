# Shift

A small native macOS controller bridge for MyWhoosh. Apple Silicon and Intel, macOS 13+.

## Use

1. Pair a Shanwan, Xbox-compatible or another supported gamepad in macOS Bluetooth settings.
2. Open Shift and allow local network access.
3. Choose **Shift** in the training app’s controller pairing screen and enable MyShift in MyWhoosh.
4. D-pad right shifts up; left shifts down. Swap direction or disable hold-to-repeat in Shift.

The controller and training app communicate over the local network. Shift does not replace a smart trainer. Supports macOS gamepads, Click V1 (unencrypted), Click V2 (firmware-dependent activation) and learnable keyboard/HID remotes. Six gamepad layouts and optional app-targeted keyboard output are available. See SUPPORT.md for exact support and limits.

## Build and test

Install Xcode command-line tools and run `python3 scripts/build.py`. No third-party dependencies or package downloads. The build runs protocol/input and real TCP integration tests, produces a universal app and creates a ZIP. Set `SHIFT_SIGN_IDENTITY` to an available signing identity if desired. Signing credentials are never stored in the repository.

## Distribution

The initial release is signed but is **not Apple-notarized**. macOS may block first launch; use Apple’s documented approval flow for software you trust: https://support.apple.com/102445. No system-wide security settings need to be disabled.

## Integration

Open `shift://open` from another app to bring Shift to the foreground. The scheme does not expose remote shift commands. Link to the website as a fallback when Shift is not installed. The protocol bridge is isolated in Sources/Bridge.swift and can be reused with the MIT attribution.

## Privacy

No accounts, cloud sync, analytics or personal workout data. Only a random device identifier, app identity and controller commands are exchanged on the LAN. MyWhoosh is an independent application. Shift is an independent project.

## License

MIT. Protocol attribution: THIRD_PARTY_NOTICES.md.

## Click V2 — ab Shift 1.1 (Beta)
In Shift „Zwift Click V2“ wählen, „V2 suchen“ drücken und beide Controller
nacheinander verbinden. Bluetooth für Shift erlauben. Anschließend Shift
in MyWhoosh als Controller auswählen. +/−, invertierte Richtung und
Haltewiederholung verwenden dieselbe OpenBikeControl-Verbindung wie Gamepads.
„Tasten kommen an“ bestätigt erst ein echtes, gültiges Tastenpaket.

Die beiden V2-Pods können Tasten spiegeln; Shift verarbeitet diese einmal.
Der linke V2 benötigt je nach Firmware eine zeitlich begrenzte Freigabe
durch Zwift. Beide Controller dort aktivieren, Zwift schließen, in Shift
neu verbinden. Shift erneuert die Freigabe nicht automatisch und sammelt
keine Zwift-Zugangsdaten. Noch kein physischer V2-/Fahrtest durchgeführt.
Die App bleibt Apple-Development-signiert und nicht notarisiert.

Protokollquelle: thomaschampagne/zwiftboard, MIT, Revision
ee4b1f2156d316398f71aeb09b67282901456b8e. Vollständige Attribution in
THIRD_PARTY_NOTICES.md. Kein Code der nichtkommerziell lizenzierten
BikeControl-App wurde übernommen.

## Shift 1.2
Controllerquelle aus Gamepad, Click V1, Click V2 oder Tastatur wählen.
Gamepad-Belegung über das Menü ändern. HID-Tasten mit „Hoch“/„Runter“ anlernen.
Für die Tastenausgabe eine laufende Ziel-App und zwei Tasten wählen und
anschließend ausdrücklich aktivieren. Bedienungshilfen werden nur auf
Anforderung geöffnet; Freigaben werden nicht automatisch gesetzt.
Beim Lernen wird die Ausgabe deaktiviert. Quellwechsel, Programmende und
Trennung geben gehaltene Tasten frei; eigene Ausgaben werden nicht erneut
als Eingabe verarbeitet. Keine Texteingaben oder Verlaufsspeicherung.
Vollständige Kompatibilitätsmatrix: [SUPPORT.md](SUPPORT.md).

## Shift 1.3 — MyWhoosh und beide Click V2
Beim ersten Start führt der Assistent durch Paarverbindung, MyWhoosh und
separaten Plus-/Minus-Test. [Deutschsprachige Startanleitung](QUICKSTART-DE.md).
Lokale Profile lassen sich speichern und ohne Geräte-IDs oder Berechtigungen
teilen. Das Profil Profiles/MyWhoosh-Click-V2.json passt zu diesem Setup.

Zusätzlich: älteres unverschlüsseltes Zwift Ride (linker BLE-Anker) und
optionale OpenBikeControl-BLE-Geräteemulation. Das ist keine Zwift-/FTMS-
Emulation; die Empfänger-App muss OpenBikeControl über BLE unterstützen.
Ride-/BLE-Hardwaretests stehen noch aus. [SUPPORT.md](SUPPORT.md) ist maßgeblich.

Protokollreferenzen: https://www.makinolo.com/blog/2024/07/26/zwift-ride-protocol/
und https://github.com/OpenBikeControl/openbikecontrol-protocol/blob/main/BLE.md.

## Shift 1.4
Adaptive Orbit- und Eingabeanimationen mit Systemvorgabe, voller oder reduzierter Bewegung. Animationen pausieren bei inaktiver App. Behebt die wiederholte MyWhoosh-Trennung durch dessen Nullbyte nach App Information. 99 Prüfungen plus TCP-Integration bestanden.

[Alle Apps und Downloads](https://joshuaforster.de/apps/)

# Shift

A small native macOS controller bridge for MyWhoosh. Apple Silicon and Intel, macOS 13+.

## Use

1. Pair a Shanwan, Xbox-compatible or another supported gamepad in macOS Bluetooth settings.
2. Open Shift and allow local network access.
3. Choose **Shift** in the training app’s controller pairing screen and enable MyShift in MyWhoosh.
4. D-pad right shifts up; left shifts down. Swap direction or disable hold-to-repeat in Shift.

The controller and training app communicate over the local network. Shift does not replace a smart trainer. Supports OS gamepads and direct Zwift Click V2 pairing (beta, firmware-dependent activation may be required). Keyboard-mode Anki remotes are not supported.

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

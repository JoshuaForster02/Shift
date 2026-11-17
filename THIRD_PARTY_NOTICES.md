# Third-party notices

Shift implements the OpenBikeControl protocol from its public specification.
Specification: https://github.com/OpenBikeControl/openbikecontrol-protocol

MIT License

Copyright (c) 2024 OpenBikeControl Protocol Contributors

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.


## Zwift Click V2 protocol reference

Click V2 protocol reference: https://github.com/thomaschampagne/zwiftboard
Revision: ee4b1f2156d316398f71aeb09b67282901456b8e
Shift uses the documented UUIDs, activation sequence and active-low button bitmap.
No automatic Zwift account/server activation is implemented.

MIT License

Copyright (c) 2026 Thomas Champagne

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.


## Zwift Ride protocol facts
Independent adapter based on the published protocol description by Makinolo:
https://www.makinolo.com/blog/2024/07/26/zwift-ride-protocol/
No BikeControl application code is included.

## Direct Connect wire format
The virtual test trainer is an original implementation of BLE data transported over TCP. Protocol research references: https://support.wahoofitness.com/hc/en-us/articles/360018905100 and the independently researched format at https://github.com/elfrances/wahoo-fitness-tnp . No implementation code or specification text from that project is bundled. Bluetooth SIG UUIDs and FTMS/Cycling Power field formats are interoperability identifiers and wire formats.

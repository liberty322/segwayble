# Segway-Ninebot BLE App

Flutter research app for Segway-Ninebot electric vehicles over Bluetooth Low Energy.

## Features
- Live telemetry (speed, battery, power, range)
- Vehicle control (power on/off, seat unlock)
- Ride recording with CSV export
- Speed/telemetry charts
- Support for 66+ device models via OMS configs
- Full Gen2/Gen3 protocol implementation

## Supported Devices
Any Segway-Ninebot vehicle using BLE Encryption2 protocol.
See [protocol documentation](https://nootnooot.codeberg.page/segway-ninebot-ble/).

## Building
```bash
flutter pub get
flutter run
```

Requires Flutter 3.x, iOS 14+ or Android 8+.

## Connecting

Tap a scanned device and choose one of two flows:

- **New pairing** — press the button on the vehicle when prompted; the app runs `SET_PWD` and captures a fresh session password. Read-only telemetry will work, but vehicle actions (power on/off, seat open) will be silently rejected by the device until you also supply the **command ident** — see below.
- **Connect with password** — for devices previously paired via the official Segway app. You need two 16-byte hex values from your iOS backup:
  - `{serialNumber}_decrypt` → session password
  - `{serialNumber}_ident` → command ident (required for writes)

Both are pasted in the **Import Credentials** dialog. Easier option: hit **Scan setup QR** and point the camera at a `segway://credentials?…` QR. Format and a Python generator are documented at [nootnooot.codeberg.page/segway-ninebot-ble/credentials-qr](https://nootnooot.codeberg.page/segway-ninebot-ble/credentials-qr/).

Values persist in the local SQLite DB — after one successful connect you can reconnect to the same vehicle offline without re-entering anything.

## Protocol Documentation
Full protocol docs: [nootnooot.codeberg.page/segway-ninebot-ble](https://nootnooot.codeberg.page/segway-ninebot-ble/)

## License

Licensed under the Apache License, Version 2.0 — see [LICENSE](LICENSE) and [NOTICE](NOTICE).

Unofficial and independently developed through reverse engineering for interoperability; not affiliated with or endorsed by Segway/Ninebot. "Segway" and "Ninebot" are trademarks of their respective owners, used only to identify the hardware this app interoperates with. Use only on vehicles you own.

# BLE Device Controller

Flutter app for controlling a BLE device based on protocol analysis from btsnoop_hci.log.

## Device Information

- **Target Address**: `62:FA:DB:F9:85:E9`
- **Protocol**: Custom UART-over-BLE
- **Services**:
  - `FFE9`: Write characteristic (commands)
  - `FFE4`: Notify characteristic (responses)

## Protocol Format

```
[Header: 20 00 3a 26] [Cmd] [Length] [Data...] [Footer: 0d 0a]
```

### Command Types

| Cmd | Description |
|-----|-------------|
| 0xa2 | Poll/Heartbeat |
| 0xa3 | Control command |

### Example Packets

```
Poll:    20 00 3a 26 a2 02 62 fa 26 02 0d 0a
Control: 20 00 3a 26 a3 0d 62 fa [params...] 0d 0a
```

## Setup

### 1. Create Flutter project

```bash
cd ble_device_controller
flutter create . --org com.example
```

### 2. Install dependencies

```bash
flutter pub get
```

### 3. iOS Setup

Add to `ios/Runner/Info.plist`:

```xml
<key>NSBluetoothAlwaysUsageDescription</key>
<string>This app uses Bluetooth to communicate with BLE devices</string>
<key>NSBluetoothPeripheralUsageDescription</key>
<string>This app uses Bluetooth to communicate with BLE devices</string>
<key>UIBackgroundModes</key>
<array>
    <string>bluetooth-central</string>
</array>
```

### 4. Run

```bash
flutter run
```

## Usage

1. **Scan**: Tap the scan button to find nearby BLE devices
2. **Connect**: Tap "Connect" on your target device (highlighted if address matches)
3. **Control**: Use the control screen to:
   - Turn device on/off
   - Adjust speed (0-100%)
   - Send preset commands
   - Send raw hex commands

## Files

```
lib/
├── main.dart                     # App entry point
├── services/
│   ├── ble_service.dart          # BLE connection handling
│   └── device_protocol.dart      # Protocol encoding/decoding
└── screens/
    ├── scan_screen.dart          # Device scanning UI
    └── control_screen.dart       # Device control UI
```

## Decoded Commands from btsnoop

| Action | Hex Data |
|--------|----------|
| Poll | `20003a26a20262fa26020d0a` |
| Turn On | `20003a26a30d62fa0100ff3280...` |
| Turn Off | `20003a26a30d62fa0000ff3280...` |
| Speed Control | `20003a26a30d62fa0100ff[speed]...` |

## Troubleshooting

- **No devices found**: Ensure Bluetooth is on and location permission granted
- **Connection fails**: Device may be out of range or already connected elsewhere
- **Commands not working**: Check the log viewer for TX/RX messages

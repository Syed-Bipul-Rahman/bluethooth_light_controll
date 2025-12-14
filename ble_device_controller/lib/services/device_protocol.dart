import 'dart:typed_data';

/// Device Protocol based on btsnoop_hci.log analysis
///
/// Packet Structure:
/// [Header: 20 00 3a 26] [Cmd: a2/a3] [Length] [Data...] [Footer: 0d 0a]
///
/// Command Types:
/// - 0xa2: Poll/Status query (heartbeat)
/// - 0xa3: Control command with parameters
class DeviceProtocol {
  // Protocol constants from btsnoop analysis
  static const List<int> HEADER = [0x20, 0x00, 0x3a, 0x26];
  static const List<int> FOOTER = [0x0d, 0x0a]; // CRLF

  // Command types
  static const int CMD_POLL = 0xa2;
  static const int CMD_CONTROL = 0xa3;

  // Device identifier from log
  static const List<int> DEVICE_ID = [0x62, 0xfa];

  // Service UUIDs discovered from the device
  static const String SERVICE_UUID_FFE9 = "0000ffe9-0000-1000-8000-00805f9b34fb";
  static const String SERVICE_UUID_FFE4 = "0000ffe4-0000-1000-8000-00805f9b34fb";
  static const String SERVICE_UUID_AE01 = "0000ae01-0000-1000-8000-00805f9b34fb";
  static const String SERVICE_UUID_AE02 = "0000ae02-0000-1000-8000-00805f9b34fb";

  // Characteristic UUIDs (derived from handles in btsnoop)
  // Handle 0x0020 is in service FFE9 (0x001E-0x0021)
  static const String CHAR_UUID_WRITE = "0000ffe9-0000-1000-8000-00805f9b34fb";
  // Handle 0x001B is in service FFE4 (0x0019-0x001D) - for notifications
  static const String CHAR_UUID_NOTIFY = "0000ffe4-0000-1000-8000-00805f9b34fb";

  // Target device address from btsnoop
  static const String TARGET_DEVICE_ADDRESS = "62:FA:DB:F9:85:E9";

  /// Build a poll/heartbeat packet
  /// Based on: 20003a26a20262fa26020d0a
  static Uint8List buildPollPacket() {
    return Uint8List.fromList([
      ...HEADER,        // 20 00 3a 26
      CMD_POLL,         // a2
      0x02,             // length
      ...DEVICE_ID,     // 62 fa
      0x26, 0x02,       // additional data
      ...FOOTER,        // 0d 0a
    ]);
  }

  /// Build a control command packet
  /// Based on: 20003a26a30d62fa[params]0d0a
  ///
  /// Parameters decoded from btsnoop:
  /// - enabled: 0x00 or 0x01
  /// - mode: control mode byte
  /// - value1, value2: 16-bit values (little-endian)
  /// - flags: additional control flags
  static Uint8List buildControlPacket({
    required int enabled,
    required int mode,
    required int value1,
    required int value2,
    int flags = 0xff,
  }) {
    // Calculate checksum (sum of data bytes)
    int checksum = _calculateChecksum([
      enabled, mode,
      value1 & 0xff, (value1 >> 8) & 0xff,
      value2 & 0xff, (value2 >> 8) & 0xff,
      flags,
    ]);

    return Uint8List.fromList([
      ...HEADER,                          // 20 00 3a 26
      CMD_CONTROL,                        // a3
      0x0d,                               // length (13 bytes)
      ...DEVICE_ID,                       // 62 fa
      enabled & 0xff,                     // enabled flag
      mode & 0xff,                        // mode
      value1 & 0xff,                      // value1 low byte
      (value1 >> 8) & 0xff,               // value1 high byte
      value2 & 0xff,                      // value2 low byte
      (value2 >> 8) & 0xff,               // value2 high byte
      0xff, 0xff, 0xff, 0xff,             // reserved/padding
      (checksum >> 8) & 0xff,             // checksum high
      checksum & 0xff,                    // checksum low
      ...FOOTER,                          // 0d 0a
    ]);
  }

  /// Build a simple on/off control packet
  static Uint8List buildOnOffPacket(bool turnOn) {
    return buildControlPacket(
      enabled: turnOn ? 0x01 : 0x00,
      mode: 0xff,
      value1: 0x3280,  // Default value from log
      value2: 0x0cff,
    );
  }

  /// Build motor/speed control packet
  /// Decoded from control commands in btsnoop
  static Uint8List buildSpeedControlPacket({
    required int speed,      // 0-100
    required int direction,  // 0 or 1
  }) {
    // Map speed to device range (based on observed values)
    int mappedSpeed = (speed * 0x1815 ~/ 100).clamp(0, 0xFFFF);

    return buildControlPacket(
      enabled: 0x01,
      mode: 0xff,
      value1: mappedSpeed,
      value2: 0xffff,
    );
  }

  /// Parse response packet
  static Map<String, dynamic>? parseResponse(Uint8List data) {
    if (data.length < 6) return null;

    // Check header
    if (data[0] != HEADER[0] || data[1] != HEADER[1]) {
      return null;
    }

    int cmdType = data[4];
    int length = data[5];

    return {
      'command': cmdType,
      'length': length,
      'data': data.sublist(6, 6 + length),
      'raw': data,
    };
  }

  /// Calculate simple checksum
  static int _calculateChecksum(List<int> data) {
    int sum = 0;
    for (var byte in data) {
      sum += byte;
    }
    return sum & 0xFFFF;
  }

  /// Convert bytes to hex string for debugging
  static String bytesToHex(Uint8List bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join('');
  }
}

/// Command presets based on btsnoop analysis
class DeviceCommands {
  /// Heartbeat/polling command
  static Uint8List get poll => DeviceProtocol.buildPollPacket();

  /// Turn device on
  static Uint8List get turnOn => DeviceProtocol.buildOnOffPacket(true);

  /// Turn device off
  static Uint8List get turnOff => DeviceProtocol.buildOnOffPacket(false);

  /// Speed control presets (decoded from btsnoop)
  static Uint8List speedLow() => DeviceProtocol.buildSpeedControlPacket(
    speed: 25,
    direction: 1,
  );

  static Uint8List speedMedium() => DeviceProtocol.buildSpeedControlPacket(
    speed: 50,
    direction: 1,
  );

  static Uint8List speedHigh() => DeviceProtocol.buildSpeedControlPacket(
    speed: 100,
    direction: 1,
  );

  /// Custom speed
  static Uint8List customSpeed(int percent) =>
    DeviceProtocol.buildSpeedControlPacket(speed: percent, direction: 1);
}

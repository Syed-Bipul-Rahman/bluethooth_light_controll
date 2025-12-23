import 'lib/services/device_protocol.dart';

void main() {
  // Test white mode packet generation
  // Expected from log: 20003a26a30d62fa0100ff32800cffffffff08f4070d0a
  // Daylight 0x0c80 = 3200K, intensity 0x32 = 50

  final packet = DeviceCommands.whiteMode(daylightKelvin: 3200, intensity: 50);
  final hex = DeviceProtocol.bytesToHex(packet);

  print("Generated white mode packet:");
  print(hex);
  print("");
  print("Expected from btsnoop log:");
  print("20003a26a30d62fa0100ff32800cffffffff08f4070d0a");
  print("");
  print("Match: ${hex == '20003a26a30d62fa0100ff32800cffffffff08f4070d0a'}");
  print("");

  // Also test with intensity 2 (0x02)
  // Expected: 20003a26a30d62fa0100ff02800cffffffff08c4070d0a
  final packet2 = DeviceCommands.whiteMode(daylightKelvin: 3200, intensity: 2);
  final hex2 = DeviceProtocol.bytesToHex(packet2);
  print("Intensity=2 packet:");
  print(hex2);
  print("Expected: 20003a26a30d62fa0100ff02800cffffffff08c4070d0a");
  print("Match: ${hex2 == '20003a26a30d62fa0100ff02800cffffffff08c4070d0a'}");
}

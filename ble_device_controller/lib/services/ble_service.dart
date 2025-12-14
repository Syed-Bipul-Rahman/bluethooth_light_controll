import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'device_protocol.dart';

enum BleConnectionState {
  disconnected,
  scanning,
  connecting,
  connected,
  error,
}

class BleService extends ChangeNotifier {
  BluetoothDevice? _connectedDevice;
  BluetoothCharacteristic? _writeCharacteristic;
  BluetoothCharacteristic? _notifyCharacteristic;

  BleConnectionState _connectionState = BleConnectionState.disconnected;
  String _statusMessage = 'Ready to scan';
  List<ScanResult> _scanResults = [];
  List<String> _logs = [];

  StreamSubscription? _scanSubscription;
  StreamSubscription? _connectionSubscription;
  StreamSubscription? _notifySubscription;
  Timer? _heartbeatTimer;

  // Getters
  BleConnectionState get connectionState => _connectionState;
  String get statusMessage => _statusMessage;
  List<ScanResult> get scanResults => _scanResults;
  List<String> get logs => List.unmodifiable(_logs);
  bool get isConnected => _connectionState == BleConnectionState.connected;
  BluetoothDevice? get connectedDevice => _connectedDevice;

  void _log(String message) {
    final timestamp = DateTime.now().toString().substring(11, 19);
    _logs.add('[$timestamp] $message');
    if (_logs.length > 100) _logs.removeAt(0);
    debugPrint('BLE: $message');
    notifyListeners();
  }

  void _setStatus(String message, [BleConnectionState? state]) {
    _statusMessage = message;
    if (state != null) _connectionState = state;
    notifyListeners();
  }

  /// Request required permissions for BLE
  Future<bool> requestPermissions() async {
    _log('Requesting permissions...');

    if (Platform.isAndroid) {
      // Request Bluetooth permissions
      Map<Permission, PermissionStatus> statuses = await [
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.locationWhenInUse,
      ].request();

      bool allGranted = statuses.values.every(
        (status) => status == PermissionStatus.granted
      );

      if (!allGranted) {
        _log('Permissions denied: $statuses');
        return false;
      }
      _log('All permissions granted');
    }

    return true;
  }

  /// Start scanning for BLE devices
  Future<void> startScan({Duration timeout = const Duration(seconds: 10)}) async {
    try {
      // Request permissions first
      bool hasPermissions = await requestPermissions();
      if (!hasPermissions) {
        _setStatus('Permissions denied', BleConnectionState.error);
        _log('Error: Required permissions not granted');
        return;
      }

      _setStatus('Scanning...', BleConnectionState.scanning);
      _scanResults.clear();
      _log('Starting BLE scan...');

      // Check if Bluetooth is on
      if (await FlutterBluePlus.adapterState.first != BluetoothAdapterState.on) {
        _setStatus('Bluetooth is off', BleConnectionState.error);
        _log('Error: Bluetooth is off');
        // Try to turn on Bluetooth
        await FlutterBluePlus.turnOn();
        return;
      }

      // Start scanning with settings
      await FlutterBluePlus.startScan(
        timeout: timeout,
        androidUsesFineLocation: true,
      );

      _scanSubscription = FlutterBluePlus.scanResults.listen((results) {
        _scanResults = results;
        _log('Found ${results.length} devices');
        notifyListeners();
      });

      // Wait for scan to complete
      await Future.delayed(timeout);
      await stopScan();

    } catch (e) {
      _setStatus('Scan error: $e', BleConnectionState.error);
      _log('Scan error: $e');
    }
  }

  /// Stop scanning
  Future<void> stopScan() async {
    await FlutterBluePlus.stopScan();
    _scanSubscription?.cancel();
    _setStatus('Scan complete. Found ${_scanResults.length} devices',
               BleConnectionState.disconnected);
    _log('Scan stopped');
  }

  /// Connect to a device
  Future<bool> connectToDevice(BluetoothDevice device) async {
    try {
      _setStatus('Connecting to ${device.platformName}...',
                 BleConnectionState.connecting);
      _log('Connecting to ${device.remoteId}...');

      // Listen for connection state changes
      _connectionSubscription = device.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected) {
          _handleDisconnect();
        }
      });

      // Connect
      await device.connect(timeout: const Duration(seconds: 15));
      _connectedDevice = device;
      _log('Connected to ${device.remoteId}');

      // Discover services
      await _discoverServices();

      _setStatus('Connected to ${device.platformName}',
                 BleConnectionState.connected);

      // Start heartbeat
      _startHeartbeat();

      return true;
    } catch (e) {
      _setStatus('Connection failed: $e', BleConnectionState.error);
      _log('Connection error: $e');
      return false;
    }
  }

  /// Discover services and characteristics
  Future<void> _discoverServices() async {
    if (_connectedDevice == null) return;

    _log('Discovering services...');
    List<BluetoothService> services = await _connectedDevice!.discoverServices();

    for (var service in services) {
      String svcUuid = service.uuid.toString().toUpperCase();
      _log('Service: $svcUuid');

      for (var char in service.characteristics) {
        String charUuid = char.uuid.toString().toUpperCase();
        String props = _getCharProperties(char);
        _log('  Char: $charUuid ($props)');

        // Find write characteristic - look for any writable characteristic
        // Priority: FFE9 > any custom service with write capability
        if (char.properties.writeWithoutResponse || char.properties.write) {
          // Prefer FFE9 service, but accept any writable char in custom services
          if (svcUuid.contains('FFE9') ||
              svcUuid.contains('FFE4') ||
              svcUuid.contains('AE') ||
              (!svcUuid.contains('1800') && !svcUuid.contains('1801') && !svcUuid.contains('180A'))) {
            if (_writeCharacteristic == null || svcUuid.contains('FFE9')) {
              _writeCharacteristic = char;
              _log('  -> Selected as WRITE characteristic');
            }
          }
        }

        // Find notify characteristic
        if (char.properties.notify || char.properties.indicate) {
          if (!svcUuid.contains('1800') && !svcUuid.contains('1801') && !svcUuid.contains('180A')) {
            if (_notifyCharacteristic == null) {
              _notifyCharacteristic = char;
              _log('  -> Selected as NOTIFY characteristic');
              await _enableNotifications(char);
            }
          }
        }
      }
    }

    if (_writeCharacteristic == null) {
      _log('ERROR: No write characteristic found!');
      _log('Trying to find ANY writable characteristic...');

      // Fallback: find ANY writable characteristic
      for (var service in services) {
        for (var char in service.characteristics) {
          if (char.properties.writeWithoutResponse || char.properties.write) {
            _writeCharacteristic = char;
            _log('Fallback WRITE: ${char.uuid}');
            break;
          }
        }
        if (_writeCharacteristic != null) break;
      }
    }

    if (_writeCharacteristic != null) {
      _log('WRITE characteristic ready: ${_writeCharacteristic!.uuid}');
    } else {
      _log('CRITICAL: Still no write characteristic!');
    }
  }

  String _getCharProperties(BluetoothCharacteristic char) {
    List<String> props = [];
    if (char.properties.read) props.add('R');
    if (char.properties.write) props.add('W');
    if (char.properties.writeWithoutResponse) props.add('WnR');
    if (char.properties.notify) props.add('N');
    if (char.properties.indicate) props.add('I');
    return props.join(',');
  }

  /// Enable notifications on a characteristic
  Future<void> _enableNotifications(BluetoothCharacteristic char) async {
    try {
      await char.setNotifyValue(true);
      _notifySubscription = char.onValueReceived.listen((value) {
        _handleNotification(Uint8List.fromList(value));
      });
      _log('Notifications enabled');
    } catch (e) {
      _log('Failed to enable notifications: $e');
    }
  }

  /// Handle incoming notifications
  void _handleNotification(Uint8List data) {
    String hex = DeviceProtocol.bytesToHex(data);
    _log('RX: $hex');

    var parsed = DeviceProtocol.parseResponse(data);
    if (parsed != null) {
      _log('Parsed: cmd=${parsed['command']}, len=${parsed['length']}');
    }
  }

  /// Send data to device
  Future<bool> sendData(Uint8List data) async {
    if (_writeCharacteristic == null) {
      // Only log once per second to avoid spam
      return false;
    }

    try {
      String hex = DeviceProtocol.bytesToHex(data);
      _log('TX: $hex');

      await _writeCharacteristic!.write(
        data.toList(),
        withoutResponse: _writeCharacteristic!.properties.writeWithoutResponse,
      );
      return true;
    } catch (e) {
      _log('Send error: $e');
      return false;
    }
  }

  /// Send poll/heartbeat packet
  Future<bool> sendPoll() async {
    return sendData(DeviceCommands.poll);
  }

  /// Send turn on command
  Future<bool> sendTurnOn() async {
    _log('Sending: Turn ON');
    return sendData(DeviceCommands.turnOn);
  }

  /// Send turn off command
  Future<bool> sendTurnOff() async {
    _log('Sending: Turn OFF');
    return sendData(DeviceCommands.turnOff);
  }

  /// Send speed control
  Future<bool> sendSpeed(int percent) async {
    _log('Sending: Speed $percent%');
    return sendData(DeviceCommands.customSpeed(percent));
  }

  /// Send custom raw command
  Future<bool> sendRawCommand(List<int> bytes) async {
    _log('Sending: Raw command');
    return sendData(Uint8List.fromList(bytes));
  }

  /// Start heartbeat timer
  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    if (_writeCharacteristic == null) {
      _log('Heartbeat NOT started - no write characteristic');
      return;
    }
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (isConnected && _writeCharacteristic != null) {
        sendPoll();
      } else {
        timer.cancel();
      }
    });
    _log('Heartbeat started (1s interval)');
  }

  /// Stop heartbeat timer
  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _log('Heartbeat stopped');
  }

  /// Handle disconnect
  void _handleDisconnect() {
    _stopHeartbeat();
    _connectedDevice = null;
    _writeCharacteristic = null;
    _notifyCharacteristic = null;
    _setStatus('Disconnected', BleConnectionState.disconnected);
    _log('Disconnected from device');
  }

  /// Disconnect from device
  Future<void> disconnect() async {
    _stopHeartbeat();
    _notifySubscription?.cancel();
    _connectionSubscription?.cancel();

    if (_connectedDevice != null) {
      try {
        await _connectedDevice!.disconnect();
      } catch (e) {
        _log('Disconnect error: $e');
      }
    }

    _handleDisconnect();
  }

  /// Clear logs
  void clearLogs() {
    _logs.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    disconnect();
    _scanSubscription?.cancel();
    super.dispose();
  }
}

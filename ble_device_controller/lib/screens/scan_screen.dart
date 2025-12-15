import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../services/ble_service.dart';
import '../services/device_protocol.dart';
import 'control_screen.dart';

class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  @override
  void initState() {
    super.initState();
    // Request permissions on start
    _requestPermissions();
  }

  Future<void> _requestPermissions() async {
    // Flutter Blue Plus handles permissions internally
    // But you may need to add permission_handler for more control
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<BleService>(
      builder: (context, bleService, child) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('BLE Device Scanner'),
            actions: [
              if (bleService.isConnected)
                TextButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const ControlScreen(),
                      ),
                    );
                  },
                  icon: const Icon(Icons.settings_remote),
                  label: const Text('Control'),
                ),
            ],
          ),
          body: Column(
            children: [
              // Status bar
              _buildStatusBar(bleService),

              // Device list
              Expanded(
                child: _buildDeviceList(bleService),
              ),

              // Log viewer
              _buildLogViewer(bleService),
            ],
          ),
          floatingActionButton: _buildScanButton(bleService),
        );
      },
    );
  }

  Widget _buildStatusBar(BleService bleService) {
    Color statusColor;
    IconData statusIcon;

    switch (bleService.connectionState) {
      case BleConnectionState.connected:
        statusColor = Colors.green;
        statusIcon = Icons.bluetooth_connected;
        break;
      case BleConnectionState.connecting:
      case BleConnectionState.scanning:
        statusColor = Colors.orange;
        statusIcon = Icons.bluetooth_searching;
        break;
      case BleConnectionState.error:
        statusColor = Colors.red;
        statusIcon = Icons.error;
        break;
      default:
        statusColor = Colors.grey;
        statusIcon = Icons.bluetooth;
    }

    return Container(
      padding: const EdgeInsets.all(12),
      color: statusColor.withOpacity(0.2),
      child: Row(
        children: [
          Icon(statusIcon, color: statusColor),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              bleService.statusMessage,
              style: TextStyle(color: statusColor),
            ),
          ),
          if (bleService.isConnected)
            TextButton(
              onPressed: () => bleService.disconnect(),
              child: const Text('Disconnect'),
            ),
        ],
      ),
    );
  }

  Widget _buildDeviceList(BleService bleService) {
    if (bleService.scanResults.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.bluetooth_disabled,
                size: 64, color: Colors.grey.shade600),
            const SizedBox(height: 16),
            Text(
              'No devices found\nTap scan to search',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ],
        ),
      );
    }

    // Sort by RSSI (strongest first) and filter out unnamed devices
    var sortedResults = List<ScanResult>.from(bleService.scanResults)
      ..sort((a, b) => b.rssi.compareTo(a.rssi));

    return ListView.builder(
      itemCount: sortedResults.length,
      itemBuilder: (context, index) {
        final result = sortedResults[index];
        final device = result.device;
        final isTargetDevice =
            device.remoteId.toString() == DeviceProtocol.TARGET_DEVICE_ADDRESS;

        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          color: isTargetDevice ? Colors.blue.withOpacity(0.2) : null,
          child: ListTile(
            leading: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.bluetooth,
                  color: isTargetDevice ? Colors.blue : Colors.grey,
                ),
                Text(
                  '${result.rssi} dBm',
                  style: const TextStyle(fontSize: 10),
                ),
              ],
            ),
            title: Text(
              device.platformName.isNotEmpty
                  ? device.platformName
                  : 'Unknown Device',
              style: TextStyle(
                fontWeight:
                    isTargetDevice ? FontWeight.bold : FontWeight.normal,
              ),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(device.remoteId.toString()),
                if (isTargetDevice)
                  const Text(
                    'TARGET DEVICE',
                    style: TextStyle(
                      color: Colors.blue,
                      fontWeight: FontWeight.bold,
                      fontSize: 10,
                    ),
                  ),
              ],
            ),
            trailing: ElevatedButton(
              onPressed:
                  bleService.connectionState == BleConnectionState.connecting
                      ? null
                      : () => _connectToDevice(bleService, device),
              child: const Text('Connect'),
            ),
          ),
        );
      },
    );
  }

  Widget _buildLogViewer(BleService bleService) {
    return Container(
      height: 150,
      decoration: BoxDecoration(
        color: Colors.black87,
        border: Border(top: BorderSide(color: Colors.grey.shade800)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            color: Colors.grey.shade900,
            child: Row(
              children: [
                const Text('Log',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.clear_all, size: 18),
                  onPressed: () => bleService.clearLogs(),
                  tooltip: 'Clear logs',
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              reverse: true,
              padding: const EdgeInsets.all(8),
              itemCount: bleService.logs.length,
              itemBuilder: (context, index) {
                final log = bleService.logs[bleService.logs.length - 1 - index];
                return Text(
                  log,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    color: log.contains('Error')
                        ? Colors.red
                        : log.contains('TX:')
                            ? Colors.green
                            : log.contains('RX:')
                                ? Colors.cyan
                                : Colors.white70,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScanButton(BleService bleService) {
    final isScanning =
        bleService.connectionState == BleConnectionState.scanning;

    return FloatingActionButton.extended(
      onPressed: isScanning
          ? () => bleService.stopScan()
          : () => bleService.startScan(),
      icon: Icon(isScanning ? Icons.stop : Icons.search),
      label: Text(isScanning ? 'Stop' : 'Scan'),
      backgroundColor: isScanning ? Colors.red : Colors.blue,
    );
  }

  Future<void> _connectToDevice(
      BleService bleService, BluetoothDevice device) async {
    final success = await bleService.connectToDevice(device);

    if (success && mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const ControlScreen()),
      );
    }
  }
}

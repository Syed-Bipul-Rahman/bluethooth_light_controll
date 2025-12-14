import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/ble_service.dart';
import '../services/device_protocol.dart';

class ControlScreen extends StatefulWidget {
  const ControlScreen({super.key});

  @override
  State<ControlScreen> createState() => _ControlScreenState();
}

class _ControlScreenState extends State<ControlScreen> {
  double _speedValue = 50;
  double _brightnessValue = 50;
  bool _fanOn = false;
  bool _lightOn = false;
  final TextEditingController _rawCommandController = TextEditingController();

  @override
  void dispose() {
    _rawCommandController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<BleService>(
      builder: (context, bleService, child) {
        // Navigate back if disconnected
        if (!bleService.isConnected) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) Navigator.of(context).pop();
          });
        }

        return Scaffold(
          appBar: AppBar(
            title: Text(bleService.connectedDevice?.platformName ?? 'Control'),
            actions: [
              IconButton(
                icon: const Icon(Icons.bluetooth_disabled),
                onPressed: () async {
                  await bleService.disconnect();
                  if (mounted) Navigator.of(context).pop();
                },
                tooltip: 'Disconnect',
              ),
            ],
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Connection status
                _buildStatusCard(bleService),
                const SizedBox(height: 16),

                // Power control
                _buildPowerControl(bleService),
                const SizedBox(height: 16),

                // Speed control
                _buildSpeedControl(bleService),
                const SizedBox(height: 16),

                // Quick commands
                _buildQuickCommands(bleService),
                const SizedBox(height: 16),

                // Raw command input
                _buildRawCommandInput(bleService),
                const SizedBox(height: 16),

                // Log viewer
                _buildLogViewer(bleService),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildStatusCard(BleService bleService) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: bleService.isConnected ? Colors.green : Colors.red,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    bleService.connectedDevice?.remoteId.toString() ?? 'N/A',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    bleService.statusMessage,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade400,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPowerControl(BleService bleService) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Power Control',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            // ALL ON/OFF buttons
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      await bleService.sendAllOn();
                      setState(() {
                        _fanOn = true;
                        _lightOn = true;
                      });
                    },
                    icon: const Icon(Icons.power),
                    label: const Text('ALL ON'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: (_fanOn && _lightOn) ? Colors.green : null,
                      padding: const EdgeInsets.all(12),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      await bleService.sendAllOff();
                      setState(() {
                        _fanOn = false;
                        _lightOn = false;
                      });
                    },
                    icon: const Icon(Icons.power_off),
                    label: const Text('ALL OFF'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: (!_fanOn && !_lightOn) ? Colors.red.shade700 : null,
                      padding: const EdgeInsets.all(12),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // FAN controls
            Row(
              children: [
                const Icon(Icons.air, size: 24),
                const SizedBox(width: 8),
                const Text('Fan:', style: TextStyle(fontWeight: FontWeight.bold)),
                const Spacer(),
                ElevatedButton(
                  onPressed: () async {
                    await bleService.sendFanOn();
                    setState(() => _fanOn = true);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _fanOn ? Colors.green : null,
                  ),
                  child: const Text('ON'),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () async {
                    await bleService.sendFanOff();
                    setState(() => _fanOn = false);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: !_fanOn ? Colors.red.shade700 : null,
                  ),
                  child: const Text('OFF'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // LIGHT controls
            Row(
              children: [
                const Icon(Icons.lightbulb, size: 24),
                const SizedBox(width: 8),
                const Text('Light:', style: TextStyle(fontWeight: FontWeight.bold)),
                const Spacer(),
                ElevatedButton(
                  onPressed: () async {
                    await bleService.sendLightOn();
                    setState(() => _lightOn = true);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _lightOn ? Colors.amber : null,
                  ),
                  child: const Text('ON'),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () async {
                    await bleService.sendLightOff();
                    setState(() => _lightOn = false);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: !_lightOn ? Colors.grey.shade700 : null,
                  ),
                  child: const Text('OFF'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSpeedControl(BleService bleService) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Fan Speed
            Row(
              children: [
                const Icon(Icons.air, size: 20),
                const SizedBox(width: 8),
                const Text(
                  'Fan Speed',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.blue,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    '${_speedValue.round()}%',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            Slider(
              value: _speedValue,
              min: 0,
              max: 100,
              divisions: 20,
              label: '${_speedValue.round()}%',
              onChanged: (value) {
                setState(() => _speedValue = value);
              },
              onChangeEnd: (value) {
                bleService.sendSpeed(value.round());
              },
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildSpeedButton(bleService, 'Low', 25),
                _buildSpeedButton(bleService, 'Med', 50),
                _buildSpeedButton(bleService, 'High', 75),
                _buildSpeedButton(bleService, 'Max', 100),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 8),
            // Light Brightness
            Row(
              children: [
                const Icon(Icons.lightbulb, size: 20, color: Colors.amber),
                const SizedBox(width: 8),
                const Text(
                  'Light Brightness',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.amber,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    '${_brightnessValue.round()}%',
                    style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black),
                  ),
                ),
              ],
            ),
            Slider(
              value: _brightnessValue,
              min: 0,
              max: 100,
              divisions: 20,
              activeColor: Colors.amber,
              label: '${_brightnessValue.round()}%',
              onChanged: (value) {
                setState(() => _brightnessValue = value);
              },
              onChangeEnd: (value) {
                // Map 0-100 to brightness levels (0x01 to 0x20 based on log)
                int level = (value * 0x20 ~/ 100).clamp(1, 0x20);
                bleService.sendLightBrightness(level);
              },
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildBrightnessButton(bleService, 'Dim', 25),
                _buildBrightnessButton(bleService, 'Med', 50),
                _buildBrightnessButton(bleService, 'Bright', 75),
                _buildBrightnessButton(bleService, 'Max', 100),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBrightnessButton(BleService bleService, String label, int brightness) {
    final isActive = _brightnessValue.round() == brightness;
    return ElevatedButton(
      onPressed: () {
        setState(() => _brightnessValue = brightness.toDouble());
        int level = (brightness * 0x20 ~/ 100).clamp(1, 0x20);
        bleService.sendLightBrightness(level);
      },
      style: ElevatedButton.styleFrom(
        backgroundColor: isActive ? Colors.amber : null,
        foregroundColor: isActive ? Colors.black : null,
      ),
      child: Text(label),
    );
  }

  Widget _buildSpeedButton(BleService bleService, String label, int speed) {
    final isActive = _speedValue.round() == speed;
    return ElevatedButton(
      onPressed: () {
        setState(() => _speedValue = speed.toDouble());
        bleService.sendSpeed(speed);
      },
      style: ElevatedButton.styleFrom(
        backgroundColor: isActive ? Colors.blue : null,
      ),
      child: Text(label),
    );
  }

  Widget _buildQuickCommands(BleService bleService) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Quick Commands',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ElevatedButton.icon(
                  onPressed: () => bleService.sendPoll(),
                  icon: const Icon(Icons.sync),
                  label: const Text('Poll'),
                ),
                ElevatedButton.icon(
                  onPressed: () => _sendPresetCommand(bleService, 'preset1'),
                  icon: const Icon(Icons.looks_one),
                  label: const Text('Preset 1'),
                ),
                ElevatedButton.icon(
                  onPressed: () => _sendPresetCommand(bleService, 'preset2'),
                  icon: const Icon(Icons.looks_two),
                  label: const Text('Preset 2'),
                ),
                ElevatedButton.icon(
                  onPressed: () => _sendPresetCommand(bleService, 'preset3'),
                  icon: const Icon(Icons.looks_3),
                  label: const Text('Preset 3'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _sendPresetCommand(BleService bleService, String preset) {
    // Commands decoded from btsnoop log
    Uint8List command;
    switch (preset) {
      case 'preset1':
        // From log: control with mode ff, value 0x3280
        command = DeviceProtocol.buildControlPacket(
          enabled: 1,
          mode: 0xff,
          value1: 0x3280,
          value2: 0x0cff,
        );
        break;
      case 'preset2':
        // From log: control with value 0x1815
        command = DeviceProtocol.buildControlPacket(
          enabled: 1,
          mode: 0xff,
          value1: 0x1815,
          value2: 0xffff,
        );
        break;
      case 'preset3':
        // From log: high value control
        command = DeviceProtocol.buildControlPacket(
          enabled: 1,
          mode: 0x32,
          value1: 0x8813,
          value2: 0xffff,
        );
        break;
      default:
        return;
    }
    bleService.sendData(command);
  }

  Widget _buildRawCommandInput(BleService bleService) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Raw Command (Hex)',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Enter hex bytes (e.g., 20003a26a20262fa26020d0a)',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _rawCommandController,
                    decoration: const InputDecoration(
                      hintText: 'Hex command...',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    style: const TextStyle(fontFamily: 'monospace'),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () => _sendRawCommand(bleService),
                  child: const Text('Send'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _sendRawCommand(BleService bleService) {
    final hexString = _rawCommandController.text.replaceAll(' ', '');
    if (hexString.isEmpty || hexString.length % 2 != 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invalid hex string')),
      );
      return;
    }

    try {
      final bytes = <int>[];
      for (var i = 0; i < hexString.length; i += 2) {
        bytes.add(int.parse(hexString.substring(i, i + 2), radix: 16));
      }
      bleService.sendRawCommand(bytes);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Parse error: $e')),
      );
    }
  }

  Widget _buildLogViewer(BleService bleService) {
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Communication Log',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                IconButton(
                  icon: const Icon(Icons.clear_all),
                  onPressed: () => bleService.clearLogs(),
                  tooltip: 'Clear',
                ),
              ],
            ),
          ),
          Container(
            height: 200,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.black87,
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(12),
                bottomRight: Radius.circular(12),
              ),
            ),
            child: ListView.builder(
              reverse: true,
              itemCount: bleService.logs.length,
              itemBuilder: (context, index) {
                final log = bleService.logs[bleService.logs.length - 1 - index];
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 1),
                  child: Text(
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
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

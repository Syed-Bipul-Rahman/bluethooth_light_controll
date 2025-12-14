import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/ble_service.dart';
import '../services/device_protocol.dart';

class ControlScreen extends StatefulWidget {
  const ControlScreen({super.key});

  @override
  State<ControlScreen> createState() => _ControlScreenState();
}

class _ControlScreenState extends State<ControlScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // White mode state
  double _whiteDaylight = 4600;
  double _whiteIntensity = 50;

  // Effect mode state
  LightMode _selectedEffect = LightMode.candle;
  double _effectDaylight = 4600;
  double _effectIntensity = 50;
  double _effectFrequency = 5;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(_onTabChanged);

    // Send initial White mode command after widget is built
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final bleService = context.read<BleService>();
      _sendWhiteMode(bleService);
    });
  }

  void _onTabChanged() {
    if (!_tabController.indexIsChanging) {
      final bleService = context.read<BleService>();
      if (_tabController.index == 0) {
        _sendWhiteMode(bleService);
      } else {
        _sendEffectMode(bleService);
      }
    }
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  void _sendWhiteMode(BleService bleService) {
    bleService.sendWhiteMode(
      daylightKelvin: _whiteDaylight.round(),
      intensity: _whiteIntensity.round(),
    );
  }

  void _sendEffectMode(BleService bleService) {
    bleService.sendEffectMode(
      mode: _selectedEffect,
      intensity: _effectIntensity.round(),
      daylightKelvin: _effectDaylight.round(),
      frequency: _effectFrequency.round(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<BleService>(
      builder: (context, bleService, child) {
        if (!bleService.isConnected) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) Navigator.of(context).pop();
          });
        }

        return Scaffold(
          appBar: AppBar(
            title: Text(bleService.connectedDevice?.platformName ?? 'Light Control'),
            actions: [
              IconButton(
                icon: const Icon(Icons.power_settings_new),
                onPressed: () => bleService.sendLightOff(),
                tooltip: 'Turn Off',
              ),
              IconButton(
                icon: const Icon(Icons.bluetooth_disabled),
                onPressed: () async {
                  await bleService.disconnect();
                  if (mounted) Navigator.of(context).pop();
                },
                tooltip: 'Disconnect',
              ),
            ],
            bottom: TabBar(
              controller: _tabController,
              tabs: const [
                Tab(icon: Icon(Icons.wb_sunny), text: 'White'),
                Tab(icon: Icon(Icons.auto_awesome), text: 'Effect'),
              ],
            ),
          ),
          body: TabBarView(
            controller: _tabController,
            children: [
              _buildWhiteModeTab(bleService),
              _buildEffectModeTab(bleService),
            ],
          ),
        );
      },
    );
  }

  Widget _buildWhiteModeTab(BleService bleService) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildStatusCard(bleService),
          const SizedBox(height: 24),
          _buildWhiteDaylightControl(bleService),
          const SizedBox(height: 24),
          _buildWhiteIntensityControl(bleService),
          const SizedBox(height: 24),
          _buildLogViewer(bleService),
        ],
      ),
    );
  }

  Widget _buildWhiteDaylightControl(BleService bleService) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.wb_twilight, color: Colors.orange),
                const SizedBox(width: 8),
                const Text(
                  'Daylight',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.orange.shade300, Colors.blue.shade200],
                    ),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    '${_whiteDaylight.round()}K',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Text('2700K', style: TextStyle(fontSize: 12, color: Colors.orange)),
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      activeTrackColor: Colors.orange,
                      inactiveTrackColor: Colors.blue.shade100,
                      thumbColor: Colors.white,
                      overlayColor: Colors.orange.withOpacity(0.2),
                    ),
                    child: Slider(
                      value: _whiteDaylight,
                      min: 2700,
                      max: 6500,
                      divisions: 38,
                      label: '${_whiteDaylight.round()}K',
                      onChanged: (value) {
                        setState(() => _whiteDaylight = value);
                      },
                      onChangeEnd: (value) => _sendWhiteMode(bleService),
                    ),
                  ),
                ),
                const Text('6500K', style: TextStyle(fontSize: 12, color: Colors.blue)),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildDaylightPresetButton(bleService, 'Warm', 2700, Colors.orange),
                _buildDaylightPresetButton(bleService, 'Neutral', 4600, Colors.amber),
                _buildDaylightPresetButton(bleService, 'Cool', 5500, Colors.lightBlue),
                _buildDaylightPresetButton(bleService, 'Daylight', 6500, Colors.blue),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDaylightPresetButton(
      BleService bleService, String label, int kelvin, Color color) {
    final isActive = (_whiteDaylight - kelvin).abs() < 100;
    return ElevatedButton(
      onPressed: () {
        setState(() => _whiteDaylight = kelvin.toDouble());
        _sendWhiteMode(bleService);
      },
      style: ElevatedButton.styleFrom(
        backgroundColor: isActive ? color : null,
        foregroundColor: isActive ? Colors.white : null,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      child: Text(label),
    );
  }

  Widget _buildWhiteIntensityControl(BleService bleService) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.brightness_6, color: Colors.amber),
                const SizedBox(width: 8),
                const Text(
                  'Intensity',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.amber,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    '${_whiteIntensity.round()}%',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.brightness_low, size: 20),
                Expanded(
                  child: Slider(
                    value: _whiteIntensity,
                    min: 0,
                    max: 100,
                    divisions: 20,
                    activeColor: Colors.amber,
                    label: '${_whiteIntensity.round()}%',
                    onChanged: (value) {
                      setState(() => _whiteIntensity = value);
                    },
                    onChangeEnd: (value) => _sendWhiteMode(bleService),
                  ),
                ),
                const Icon(Icons.brightness_high, size: 20),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildIntensityPresetButton(bleService, '25%', 25, true),
                _buildIntensityPresetButton(bleService, '50%', 50, true),
                _buildIntensityPresetButton(bleService, '75%', 75, true),
                _buildIntensityPresetButton(bleService, '100%', 100, true),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIntensityPresetButton(
      BleService bleService, String label, int value, bool isWhiteMode) {
    final currentValue = isWhiteMode ? _whiteIntensity : _effectIntensity;
    final isActive = currentValue.round() == value;
    return ElevatedButton(
      onPressed: () {
        if (isWhiteMode) {
          setState(() => _whiteIntensity = value.toDouble());
          _sendWhiteMode(bleService);
        } else {
          setState(() => _effectIntensity = value.toDouble());
          _sendEffectMode(bleService);
        }
      },
      style: ElevatedButton.styleFrom(
        backgroundColor: isActive ? Colors.amber : null,
        foregroundColor: isActive ? Colors.black : null,
      ),
      child: Text(label),
    );
  }

  Widget _buildEffectModeTab(BleService bleService) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildStatusCard(bleService),
          const SizedBox(height: 16),
          _buildEffectSelector(bleService),
          const SizedBox(height: 16),
          if (_selectedEffect.hasDaylight) ...[
            _buildEffectDaylightControl(bleService),
            const SizedBox(height: 16),
          ],
          _buildEffectIntensityControl(bleService),
          const SizedBox(height: 16),
          _buildEffectFrequencyControl(bleService),
          const SizedBox(height: 16),
          _buildLogViewer(bleService),
        ],
      ),
    );
  }

  Widget _buildEffectSelector(BleService bleService) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.auto_awesome, color: Colors.purple),
                SizedBox(width: 8),
                Text(
                  'Effect Mode',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: LightMode.effectModes.map((mode) {
                final isSelected = _selectedEffect == mode;
                return ChoiceChip(
                  label: Text(mode.displayName),
                  selected: isSelected,
                  onSelected: (selected) {
                    if (selected) {
                      setState(() => _selectedEffect = mode);
                      _sendEffectMode(bleService);
                    }
                  },
                  selectedColor: Colors.purple.shade300,
                  avatar: isSelected
                      ? const Icon(Icons.check, size: 18)
                      : _getEffectIcon(mode),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget? _getEffectIcon(LightMode mode) {
    IconData? iconData;
    switch (mode) {
      case LightMode.candle:
        iconData = Icons.local_fire_department;
        break;
      case LightMode.pulse:
        iconData = Icons.waves;
        break;
      case LightMode.cctloop:
        iconData = Icons.loop;
        break;
      case LightMode.flush:
        iconData = Icons.flash_on;
        break;
      case LightMode.lightning:
        iconData = Icons.bolt;
        break;
      case LightMode.tv:
        iconData = Icons.tv;
        break;
      case LightMode.paparazzi:
        iconData = Icons.camera;
        break;
      case LightMode.breathing:
        iconData = Icons.air;
        break;
      case LightMode.fireworks:
        iconData = Icons.celebration;
        break;
      case LightMode.blast:
        iconData = Icons.blur_on;
        break;
      case LightMode.badBulb:
        iconData = Icons.lightbulb_outline;
        break;
      case LightMode.welding:
        iconData = Icons.construction;
        break;
      default:
        return null;
    }
    return Icon(iconData, size: 18);
  }

  Widget _buildEffectDaylightControl(BleService bleService) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.wb_twilight, color: Colors.orange),
                const SizedBox(width: 8),
                const Text(
                  'Daylight',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.orange.shade300, Colors.blue.shade200],
                    ),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    '${_effectDaylight.round()}K',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Text('2700K', style: TextStyle(fontSize: 12, color: Colors.orange)),
                Expanded(
                  child: Slider(
                    value: _effectDaylight,
                    min: 2700,
                    max: 6500,
                    divisions: 38,
                    activeColor: Colors.orange,
                    label: '${_effectDaylight.round()}K',
                    onChanged: (value) {
                      setState(() => _effectDaylight = value);
                    },
                    onChangeEnd: (value) => _sendEffectMode(bleService),
                  ),
                ),
                const Text('6500K', style: TextStyle(fontSize: 12, color: Colors.blue)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEffectIntensityControl(BleService bleService) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.brightness_6, color: Colors.amber),
                const SizedBox(width: 8),
                const Text(
                  'Intensity',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.amber,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    '${_effectIntensity.round()}%',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.brightness_low, size: 20),
                Expanded(
                  child: Slider(
                    value: _effectIntensity,
                    min: 0,
                    max: 100,
                    divisions: 20,
                    activeColor: Colors.amber,
                    label: '${_effectIntensity.round()}%',
                    onChanged: (value) {
                      setState(() => _effectIntensity = value);
                    },
                    onChangeEnd: (value) => _sendEffectMode(bleService),
                  ),
                ),
                const Icon(Icons.brightness_high, size: 20),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEffectFrequencyControl(BleService bleService) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.speed, color: Colors.green),
                const SizedBox(width: 8),
                const Text(
                  'Frequency',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.green,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    '${_effectFrequency.round()}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Text('1', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                Expanded(
                  child: Slider(
                    value: _effectFrequency,
                    min: 1,
                    max: 10,
                    divisions: 9,
                    activeColor: Colors.green,
                    label: '${_effectFrequency.round()}',
                    onChanged: (value) {
                      setState(() => _effectFrequency = value);
                    },
                    onChangeEnd: (value) => _sendEffectMode(bleService),
                  ),
                ),
                const Text('10', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [1, 3, 5, 7, 10].map((freq) {
                final isActive = _effectFrequency.round() == freq;
                return ElevatedButton(
                  onPressed: () {
                    setState(() => _effectFrequency = freq.toDouble());
                    _sendEffectMode(bleService);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isActive ? Colors.green : null,
                    foregroundColor: isActive ? Colors.white : null,
                    minimumSize: const Size(50, 36),
                  ),
                  child: Text('$freq'),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusCard(BleService bleService) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
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
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade400),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLogViewer(BleService bleService) {
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Log',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                ),
                IconButton(
                  icon: const Icon(Icons.clear_all, size: 20),
                  onPressed: () => bleService.clearLogs(),
                  tooltip: 'Clear',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ),
          Container(
            height: 120,
            padding: const EdgeInsets.all(8),
            decoration: const BoxDecoration(
              color: Colors.black87,
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(12),
                bottomRight: Radius.circular(12),
              ),
            ),
            child: ListView.builder(
              reverse: true,
              itemCount: bleService.logs.length,
              itemBuilder: (context, index) {
                final log = bleService.logs[bleService.logs.length - 1 - index];
                return Text(
                  log,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 10,
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
}

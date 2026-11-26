/// Lights — bit toggles on rFunBool + one-shot "flash lights" action.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/logger.dart';
import '../../core/protocol/nb_protocol.dart';
import '../../providers/connection_provider.dart';
import '../../providers/vehicle_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/bit_toggle_row.dart';
import '../../widgets/setting_row.dart';

class LightsScreen extends ConsumerStatefulWidget {
  const LightsScreen({super.key});

  @override
  ConsumerState<LightsScreen> createState() => _LightsScreenState();
}

class _LightsScreenState extends ConsumerState<LightsScreen> {
  VehicleNotifier? _notifier;

  @override
  void initState() {
    super.initState();
    talker.info('Screen[Lights] mounted');
    _notifier = ref.read(vehicleProvider.notifier);
    _notifier!.resumePolling(
      {PollTier.slow, PollTier.settings},
      by: 'Lights',
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _notifier!.refreshSettingsRegisters();
    });
  }

  @override
  void dispose() {
    talker.info('Screen[Lights] disposed');
    _notifier?.pausePolling(by: 'Lights');
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vehicle = ref.watch(vehicleProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Lights')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 16),
        children: [
          SettingSection(
            title: 'Toggles',
            description:
                'Bits of rFunBool (DIS 0x7D). Writes are read-back verified; '
                'the device may ignore a bit if the feature is not fitted.',
            children: [
              BitToggleRow(
                label: 'Streamline taillight',
                subtitle: 'Decorative taillight strip',
                icon: Icons.lightbulb_outline,
                target: boardDis,
                register: regFunBool,
                bit: 10, // 0x0400
                currentRegisterValue: vehicle.funBool,
                onPatch: (v) =>
                    ref.read(vehicleProvider.notifier).patch(funBool: v),
              ),
              BitToggleRow(
                label: 'Indicator auto-off',
                subtitle: 'Turn signals cancel after a few seconds',
                icon: Icons.signpost_outlined,
                target: boardDis,
                register: regFunBool,
                bit: 11, // 0x0800
                currentRegisterValue: vehicle.funBool,
                onPatch: (v) =>
                    ref.read(vehicleProvider.notifier).patch(funBool: v),
              ),
            ],
          ),
          SettingSection(
            title: 'Actions',
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _sendFlash(context),
                        icon: const Icon(Icons.flash_on),
                        label: const Text('Flash lights'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _sendHonk(context),
                        icon: const Icon(Icons.campaign),
                        label: const Text('Honk + flash'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              'Light level (DIS 0x7B), handle RGB (0x8E/0x9D) and HEP light '
              '(0x0E) are known but not surfaced yet.',
              style: TextStyle(
                color: AppTheme.textSecondary.withValues(alpha: 0.7),
                fontSize: 12,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _sendFlash(BuildContext context) {
    final conn = ref.read(connectionProvider.notifier);
    final frame = buildPlayLight(gen: conn.gen);
    talker.info('VehicleAction playLight: sending frame');
    conn.sendOnly(frame);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Flash lights sent'),
      duration: Duration(seconds: 2),
    ));
  }

  void _sendHonk(BuildContext context) {
    final conn = ref.read(connectionProvider.notifier);
    final frame = buildPlaySound(gen: conn.gen);
    talker.info('VehicleAction playSound: sending frame');
    conn.sendOnly(frame);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Honk + flash lights sent'),
      duration: Duration(seconds: 2),
    ));
  }
}

/// Speed & Safety settings. Matches the official E-series app layout:
/// a 4-preset "speed safety lock" and the two read-only max-speed values.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/logger.dart';
import '../../core/protocol/nb_protocol.dart';
import '../../providers/connection_provider.dart';
import '../../providers/vehicle_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/setting_row.dart';

// device_ui_speed_safety_lock.json: rLimitSpeed (DIS 0x93), radio picker.
const _speedLockPresets = <int, String>{
  0: 'Off',
  25: '25 km/h',
  45: '45 km/h',
  60: '60 km/h',
};

class SpeedSafetyScreen extends ConsumerStatefulWidget {
  const SpeedSafetyScreen({super.key});

  @override
  ConsumerState<SpeedSafetyScreen> createState() =>
      _SpeedSafetyScreenState();
}

class _SpeedSafetyScreenState extends ConsumerState<SpeedSafetyScreen> {
  VehicleNotifier? _notifier;

  @override
  void initState() {
    super.initState();
    talker.info('Screen[SpeedSafety] mounted');
    _notifier = ref.read(vehicleProvider.notifier);
    _notifier!.resumePolling(
      {PollTier.slow, PollTier.settings},
      by: 'SpeedSafety',
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _notifier!.refreshSettingsRegisters();
    });
  }

  @override
  void dispose() {
    talker.info('Screen[SpeedSafety] disposed');
    _notifier?.pausePolling(by: 'SpeedSafety');
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vehicle = ref.watch(vehicleProvider);

    String kmhTenth(int v) => '${(v / 10).toStringAsFixed(1)} km/h';

    final currentLock = vehicle.limitSpeedRaw;
    final lockLabel = currentLock == null
        ? '—'
        : _speedLockPresets[currentLock] ?? '$currentLock km/h';

    return Scaffold(
      appBar: AppBar(title: const Text('Speed & Safety')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 16),
        children: [
          SettingSection(
            title: 'Speed',
            description:
                'The safety lock matches the official app — four presets on '
                'DIS 0x93 (rLimitSpeed).',
            children: [
              SettingRow(
                label: 'Speed safety lock',
                subtitle: 'Caps the top speed in all riding modes',
                icon: Icons.speed,
                currentValue: lockLabel,
                onTap: currentLock == null
                    ? null
                    : () => _pickSpeedLock(context, currentLock),
              ),
              SettingRow(
                label: 'Rated max speed',
                subtitle: 'Factory-rated ceiling (read-only)',
                icon: Icons.shield_outlined,
                tappable: false,
                currentValue: vehicle.ratedSpeedRaw != null
                    ? kmhTenth(vehicle.ratedSpeedRaw!)
                    : '—',
              ),
              SettingRow(
                label: 'Signage max speed',
                subtitle: 'Trip max — resets per ride',
                icon: Icons.signpost_outlined,
                tappable: false,
                currentValue: vehicle.sigMaxSpeedRaw != null
                    ? kmhTenth(vehicle.sigMaxSpeedRaw!)
                    : '—',
              ),
            ],
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              'Traction control and electric brake are on/off toggles under '
              'Features (they live on rCTLBool2 bits, not MCU levels).',
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

  void _pickSpeedLock(BuildContext context, int current) {
    final conn = ref.read(connectionProvider.notifier);
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: _speedLockPresets.entries.map((e) {
            return RadioListTile<int>(
              value: e.key,
              groupValue: current,
              title: Text(e.value),
              onChanged: (v) async {
                Navigator.of(ctx).pop();
                if (v == null) return;
                final actual = await conn.writeAndVerifyU16(
                    boardDis, regLimitSpeed, v);
                if (actual != null) {
                  ref
                      .read(vehicleProvider.notifier)
                      .patch(limitSpeedRaw: actual);
                }
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text('Speed safety lock: ${e.value}'),
                    duration: const Duration(seconds: 2),
                  ));
                }
              },
            );
          }).toList(),
        ),
      ),
    );
  }
}

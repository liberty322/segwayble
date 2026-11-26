/// Audio settings — prompt volume + sound preset + alarm volume/sensitivity.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/logger.dart';
import '../../core/protocol/nb_protocol.dart';
import '../../providers/connection_provider.dart';
import '../../providers/vehicle_provider.dart';
import '../../widgets/setting_row.dart';
import '../../widgets/value_editor.dart';

// rWarn (DIS 0x75) high byte — sound preset enum.
const _soundPresetLabels = <int, String>{
  0: 'Sound 1',
  1: 'Sound 2',
  2: 'Sound 3',
};

// rAlarmLevel (DIS 0x77) enum from device_ui_safety_set.json.
const _alarmLevelLabels = <int, String>{
  4: 'Low',
  3: 'Standard',
  2: 'High',
  1: 'Sensitive',
};

class AudioScreen extends ConsumerStatefulWidget {
  const AudioScreen({super.key});

  @override
  ConsumerState<AudioScreen> createState() => _AudioScreenState();
}

class _AudioScreenState extends ConsumerState<AudioScreen> {
  VehicleNotifier? _notifier;

  @override
  void initState() {
    super.initState();
    talker.info('Screen[Audio] mounted');
    _notifier = ref.read(vehicleProvider.notifier);
    _notifier!.resumePolling(
      {PollTier.slow, PollTier.settings},
      by: 'Audio',
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _notifier!.refreshSettingsRegisters();
    });
  }

  @override
  void dispose() {
    talker.info('Screen[Audio] disposed');
    _notifier?.pausePolling(by: 'Audio');
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vehicle = ref.watch(vehicleProvider);
    final conn = ref.read(connectionProvider.notifier);

    final warn = vehicle.warn;
    final promptVol = warn != null ? warnVolume(warn) : null;
    final preset = warn != null ? warnPreset(warn) : null;

    return Scaffold(
      appBar: AppBar(title: const Text('Audio')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 16),
        children: [
          SettingSection(
            title: 'Prompt sounds',
            description:
                'The low byte of rWarn (DIS 0x75) holds volume; the high '
                'byte selects which sound bank plays for beeps and alerts.',
            children: [
              SettingRow(
                label: 'Prompt volume',
                subtitle: '0–100%',
                icon: Icons.volume_up_outlined,
                currentValue: promptVol != null ? '$promptVol' : '—',
                onTap: warn == null
                    ? null
                    : () => _editPromptVolume(
                        context, conn, warn, promptVol ?? 0, preset ?? 0),
              ),
              SettingRow(
                label: 'Sound preset',
                icon: Icons.campaign_outlined,
                currentValue: preset != null
                    ? _soundPresetLabels[preset] ?? 'Custom ($preset)'
                    : '—',
                onTap: warn == null
                    ? null
                    : () => _pickSoundPreset(
                        context, conn, warn, promptVol ?? 0, preset ?? 0),
              ),
            ],
          ),
          SettingSection(
            title: 'Alarm',
            description: 'Triggered by motion-sensor events when locked.',
            children: [
              SettingRow(
                label: 'Alarm volume',
                subtitle: '0–100%',
                icon: Icons.notifications_active_outlined,
                currentValue: vehicle.alarmVolume != null
                    ? '${vehicle.alarmVolume}'
                    : '—',
                onTap: vehicle.alarmVolume == null
                    ? null
                    : () => Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => ValueEditor(
                            title: 'Alarm volume',
                            current: vehicle.alarmVolume!,
                            min: 0,
                            max: 100,
                            step: 5,
                            format: (v) => '$v',
                            onSave: (v) async {
                              final actual = await conn.writeAndVerifyU16(
                                  boardDis, regAlarmVolume, v);
                              if (actual != null) {
                                ref
                                    .read(vehicleProvider.notifier)
                                    .patch(alarmVolume: actual);
                              }
                              return actual;
                            },
                          ),
                        )),
              ),
              SettingRow(
                label: 'Alarm sensitivity',
                icon: Icons.sensors_outlined,
                currentValue: vehicle.alarmLevel != null
                    ? _alarmLevelLabels[vehicle.alarmLevel] ??
                        'Custom (${vehicle.alarmLevel})'
                    : '—',
                onTap: vehicle.alarmLevel == null
                    ? null
                    : () => _pickAlarmLevel(context, conn, vehicle.alarmLevel!),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _editPromptVolume(BuildContext context, ConnectionNotifier conn,
      int currentWarn, int currentVol, int preset) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ValueEditor(
        title: 'Prompt volume',
        description: 'Sound preset (Sound ${preset + 1}) is kept unchanged.',
        current: currentVol,
        min: 0,
        max: 100,
        step: 5,
        format: (v) => '$v',
        onSave: (v) async {
          final packed = packWarn(volume: v, preset: preset);
          final actual =
              await conn.writeAndVerifyU16(boardDis, regWarn, packed);
          if (actual != null) {
            ref.read(vehicleProvider.notifier).patch(warn: actual);
            return warnVolume(actual);
          }
          return null;
        },
      ),
    ));
  }

  void _pickSoundPreset(BuildContext context, ConnectionNotifier conn,
      int currentWarn, int volume, int currentPreset) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: _soundPresetLabels.entries.map((e) {
            return RadioListTile<int>(
              value: e.key,
              groupValue: currentPreset,
              title: Text(e.value),
              onChanged: (v) async {
                Navigator.of(ctx).pop();
                if (v == null) return;
                final packed = packWarn(volume: volume, preset: v);
                final actual =
                    await conn.writeAndVerifyU16(boardDis, regWarn, packed);
                if (actual != null) {
                  ref.read(vehicleProvider.notifier).patch(warn: actual);
                }
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text('Sound preset: ${e.value}'),
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

  void _pickAlarmLevel(
      BuildContext context, ConnectionNotifier conn, int currentLevel) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: _alarmLevelLabels.entries.map((e) {
            return RadioListTile<int>(
              value: e.key,
              groupValue: currentLevel,
              title: Text(e.value),
              subtitle: Text('Level ${e.key}'),
              onChanged: (v) async {
                Navigator.of(ctx).pop();
                if (v == null) return;
                final actual =
                    await conn.writeAndVerifyU16(boardDis, regAlarmLevel, v);
                if (actual != null) {
                  ref.read(vehicleProvider.notifier).patch(alarmLevel: actual);
                }
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text('Alarm sensitivity: ${e.value}'),
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

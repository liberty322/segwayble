/// Features screen — bitmask + toggle features (auto-lock, push assist, …).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/logger.dart';
import '../../core/protocol/nb_protocol.dart';
import '../../providers/vehicle_provider.dart';
import '../../widgets/bit_toggle_row.dart';
import '../../widgets/setting_row.dart';
import '../../widgets/value_editor.dart';
import '../../providers/connection_provider.dart';

class FeaturesScreen extends ConsumerStatefulWidget {
  const FeaturesScreen({super.key});

  @override
  ConsumerState<FeaturesScreen> createState() => _FeaturesScreenState();
}

class _FeaturesScreenState extends ConsumerState<FeaturesScreen> {
  VehicleNotifier? _notifier;

  @override
  void initState() {
    super.initState();
    talker.info('Screen[Features] mounted');
    _notifier = ref.read(vehicleProvider.notifier);
    _notifier!.resumePolling(
      {PollTier.slow, PollTier.settings},
      by: 'Features',
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _notifier!.refreshSettingsRegisters();
    });
  }

  @override
  void dispose() {
    talker.info('Screen[Features] disposed');
    _notifier?.pausePolling(by: 'Features');
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vehicle = ref.watch(vehicleProvider);
    final conn = ref.read(connectionProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('Features')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 16),
        children: [
          SettingSection(
            title: 'Locks',
            children: [
              SettingRow(
                label: 'Auto-lock',
                subtitle: 'Timeout before the scooter re-locks itself',
                currentValue: vehicle.autoLock != null
                    ? _autoLockLabel(vehicle.autoLock!)
                    : '—',
                icon: Icons.lock_clock,
                onTap: () {
                  if (vehicle.autoLock == null) return;
                  Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => ValueEditor(
                      title: 'Auto-lock',
                      description:
                          '0 = off; otherwise in seconds. Higher values keep '
                          'the scooter unlocked longer after stepping away.',
                      current: vehicle.autoLock!,
                      min: 0,
                      max: 600,
                      step: 30,
                      format: _autoLockLabel,
                      onSave: (v) async {
                        final actual = await conn.writeAndVerifyU16(
                            boardDis, regAutoLock, v);
                        if (actual != null) {
                          ref
                              .read(vehicleProvider.notifier)
                              .patch(autoLock: actual);
                        }
                        return actual;
                      },
                    ),
                  ));
                },
              ),
            ],
          ),
          SettingSection(
            title: 'rFunBool (DIS 0x7D)',
            description:
                'Tap to toggle. Changes are verified by reading the register '
                'back; the device may refuse to apply a bit.',
            children: [
              BitToggleRow(
                label: 'Push assist',
                subtitle: 'Walk-beside speed',
                icon: Icons.directions_walk,
                target: boardDis,
                register: regFunBool,
                bit: 1,
                currentRegisterValue: vehicle.funBool,
                onPatch: (v) =>
                    ref.read(vehicleProvider.notifier).patch(funBool: v),
              ),
              BitToggleRow(
                label: 'Parking detection',
                subtitle: 'Prevents rolling when stopped',
                icon: Icons.local_parking,
                target: boardDis,
                register: regFunBool,
                bit: 8,
                reversed: true, // spec: rFunBool mask 256 has "reverse": true
                currentRegisterValue: vehicle.funBool,
                onPatch: (v) =>
                    ref.read(vehicleProvider.notifier).patch(funBool: v),
              ),
              BitToggleRow(
                label: 'Seat detection',
                subtitle: 'Only engages motor when rider is seated',
                icon: Icons.chair_outlined,
                target: boardDis,
                register: regFunBool,
                bit: 9,
                reversed: true, // spec: rFunBool mask 512 has "reverse": true
                currentRegisterValue: vehicle.funBool,
                onPatch: (v) =>
                    ref.read(vehicleProvider.notifier).patch(funBool: v),
              ),
              BitToggleRow(
                label: 'Reverse',
                subtitle: 'Enable reverse throttle',
                icon: Icons.undo,
                target: boardDis,
                register: regFunBool,
                bit: 13,
                currentRegisterValue: vehicle.funBool,
                onPatch: (v) =>
                    ref.read(vehicleProvider.notifier).patch(funBool: v),
              ),
              BitToggleRow(
                label: 'Extended range',
                subtitle: 'Trade top speed for extra range at low battery',
                icon: Icons.battery_saver,
                target: boardDis,
                register: regFunBool,
                bit: 7, // mask 128
                currentRegisterValue: vehicle.funBool,
                onPatch: (v) =>
                    ref.read(vehicleProvider.notifier).patch(funBool: v),
              ),
              BitToggleRow(
                label: 'Show remaining range',
                subtitle: 'Display km-to-empty on the dashboard',
                icon: Icons.speed,
                target: boardDis,
                register: regFunBool,
                bit: 14, // mask 16384
                currentRegisterValue: vehicle.funBool,
                onPatch: (v) =>
                    ref.read(vehicleProvider.notifier).patch(funBool: v),
              ),
            ],
          ),
          SettingSection(
            title: 'rCtlBool2 (DIS 0x7C)',
            description:
                'Feature gates — tapping may not do anything if the device '
                'firmware does not expose the underlying feature.',
            children: [
              BitToggleRow(
                label: 'Metric / Imperial',
                subtitle: 'On = miles, off = km',
                icon: Icons.straighten,
                target: boardDis,
                register: regCtlBool2,
                bit: 1,
                currentRegisterValue: vehicle.ctlBool2,
                onPatch: (v) =>
                    ref.read(vehicleProvider.notifier).patch(ctlBool2: v),
              ),
              BitToggleRow(
                label: 'Auto park',
                icon: Icons.pause_circle_outline,
                target: boardDis,
                register: regCtlBool2,
                bit: 7,
                currentRegisterValue: vehicle.ctlBool2,
                onPatch: (v) =>
                    ref.read(vehicleProvider.notifier).patch(ctlBool2: v),
              ),
              // Electric brake — rCTLBool2 bit 10 (0x0400), reversed: set=off.
              // Gated by rFunAppBool bit 4 (0x0010) per device_ui_settings.json.
              if (((vehicle.funAppBool ?? 0) & 0x0010) != 0)
                BitToggleRow(
                  label: 'Electric brake',
                  subtitle: 'Regenerative braking',
                  icon: Icons.electric_bolt,
                  target: boardDis,
                  register: regCtlBool2,
                  bit: 10,
                  reversed: true,
                  currentRegisterValue: vehicle.ctlBool2,
                  onPatch: (v) =>
                      ref.read(vehicleProvider.notifier).patch(ctlBool2: v),
                ),
              // TCS — rCTLBool2 bit 13 (0x2000), reversed: set=off.
              // Gated by rFunAppBool2 bit 1 (0x0002).
              if (((vehicle.funAppBool2 ?? 0) & 0x0002) != 0)
                BitToggleRow(
                  label: 'Traction control',
                  subtitle: 'Prevents wheel slip on wet roads',
                  icon: Icons.compare_arrows,
                  target: boardDis,
                  register: regCtlBool2,
                  bit: 13,
                  reversed: true,
                  currentRegisterValue: vehicle.ctlBool2,
                  onPatch: (v) =>
                      ref.read(vehicleProvider.notifier).patch(ctlBool2: v),
                ),
            ],
          ),
        ],
      ),
    );
  }

  static String _autoLockLabel(int seconds) {
    if (seconds == 0) return 'Off';
    if (seconds < 60) return '${seconds}s';
    final m = seconds ~/ 60;
    final s = seconds % 60;
    if (s == 0) return '${m}m';
    return '${m}m ${s}s';
  }
}

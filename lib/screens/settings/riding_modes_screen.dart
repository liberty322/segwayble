/// Riding modes + per-mode profile editor.
///
/// Picker at top selects one of six modes via the DIS `rBool2` bitmask.
/// Below it, six rows expose the currently-active gear-profile registers
/// (top speed, acceleration, TCS, nitro, energy, sensitivity). Because
/// the scooter only maintains one active profile at a time, the rows
/// reflect whichever mode is selected right now — switching modes
/// updates all six from firmware.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/logger.dart';
import '../../core/protocol/nb_protocol.dart';
import '../../providers/connection_provider.dart';
import '../../providers/vehicle_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/setting_row.dart';
import '../../widgets/value_editor.dart';

/// Mode id → label + bitmask bit.
///
/// Bit assignments verified against the official Segway app's
/// `device_ui_gear.json` bindings:
///   eco     → mask 0x01 (bit 0)
///   coast   → mask 0x02 (bit 1)
///   furious → mask 0x04 (bit 2)
///   m1      → mask 0x08 (bit 3)
///   m2      → mask 0x10 (bit 4)
const ridingModes = <RidingMode>[
  RidingMode(bit: 0, id: 'eco', label: 'ECO', hint: 'Longest range'),
  RidingMode(bit: 1, id: 'coast', label: 'Coast', hint: 'Balanced'),
  RidingMode(bit: 2, id: 'furious', label: 'Furious', hint: 'Max performance'),
  RidingMode(bit: 3, id: 'm1', label: 'Custom M1', hint: 'User profile 1'),
  RidingMode(bit: 4, id: 'm2', label: 'Custom M2', hint: 'User profile 2'),
];

class RidingMode {
  final int bit;
  final String id;
  final String label;
  final String hint;
  const RidingMode({
    required this.bit,
    required this.id,
    required this.label,
    required this.hint,
  });
  int get mask => 1 << bit;
}

/// Return the first known riding mode whose bit is set in [mask],
/// or null if none of the [ridingModes] bits are on.
RidingMode? activeRidingMode(int? mask) {
  if (mask == null) return null;
  for (final m in ridingModes) {
    if ((mask & m.mask) != 0) return m;
  }
  return null;
}

/// Compute the new `rBool2` value after selecting [newMode]. All known
/// mode bits are cleared from [currentMask] first, then [newMode]'s
/// bit is set — preserving any unrelated higher bits the firmware may
/// toggle independently.
int rBool2ForMode(int? currentMask, RidingMode newMode) {
  var v = currentMask ?? 0;
  for (final m in ridingModes) {
    v &= ~m.mask;
  }
  v |= newMode.mask;
  return v;
}

class RidingModesScreen extends ConsumerStatefulWidget {
  const RidingModesScreen({super.key});

  @override
  ConsumerState<RidingModesScreen> createState() =>
      _RidingModesScreenState();
}

class _RidingModesScreenState extends ConsumerState<RidingModesScreen> {
  VehicleNotifier? _notifier;

  @override
  void initState() {
    super.initState();
    talker.info('Screen[RidingModes] mounted');
    _notifier = ref.read(vehicleProvider.notifier);
    _notifier!.resumePolling(
      {PollTier.slow, PollTier.settings},
      by: 'RidingModes',
    );
    // Force a full re-read — gear fields are only populated via the
    // one-shot `_readSettingsOnce` which runs on connect. If the
    // vehicle was powered off at connect time, MCU reads were skipped
    // and the values are null forever until we explicitly refresh.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _notifier!.refreshSettingsRegisters();
    });
  }

  @override
  void dispose() {
    talker.info('Screen[RidingModes] disposed');
    _notifier?.pausePolling(by: 'RidingModes');
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vehicle = ref.watch(vehicleProvider);
    final conn = ref.read(connectionProvider.notifier);

    final activeMode = activeRidingMode(vehicle.activeGearMask);

    String kmh(int v) => '$v km/h';
    String onOff(int v) => v == 0 ? 'Off' : 'On';
    String sens(int v) => v == 0
        ? 'Low'
        : v == 1
            ? 'Moderate'
            : v == 2
                ? 'High'
                : '$v';
    String tcsLvl(int v) => v == 0
        ? 'Off'
        : v == 1
            ? 'Moderate'
            : v == 2
                ? 'Strongest'
                : '$v';

    Future<void> selectMode(RidingMode m) async {
      final newMask = rBool2ForMode(vehicle.activeGearMask, m);
      final verified =
          await conn.writeAndVerifyU16(boardDis, regBool2, newMask);
      if (verified != null) {
        ref.read(vehicleProvider.notifier).patch(activeGearMask: verified);
        // After mode switch, the gear-profile registers on MCU re-point
        // at the new mode's values. Force a refresh so the rows update.
        await ref.read(vehicleProvider.notifier).refresh();
      }
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Active mode: ${m.label}'),
          duration: const Duration(seconds: 2),
        ));
      }
    }

    void openEditor({
      required String title,
      String? description,
      required int? current,
      required int min,
      required int max,
      required int step,
      required String Function(int) format,
      required int target,
      required int register,
      required void Function(int) patch,
    }) {
      if (current == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Value not loaded yet — retry in a moment'),
        ));
        return;
      }
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ValueEditor(
          title: title,
          description: description,
          current: current,
          min: min,
          max: max,
          step: step,
          format: format,
          onSave: (v) async {
            final actual = await conn.writeAndVerifyU16(target, register, v);
            if (actual != null) patch(actual);
            return actual;
          },
        ),
      ));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Riding modes')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 16),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              activeMode != null
                  ? 'Active mode: ${activeMode.label}'
                  : 'No active mode selected',
              style: const TextStyle(
                color: AppTheme.primary,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 12),
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: AppTheme.card,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: ridingModes
                  .map((m) => _ModeTile(
                        mode: m,
                        selected: activeMode?.id == m.id,
                        onTap: () => selectMode(m),
                      ))
                  .toList(),
            ),
          ),
          const SizedBox(height: 16),
          SettingSection(
            title: 'Active profile',
            description: activeMode == null
                ? 'Select a mode above to edit its profile.'
                : 'Edits affect the ${activeMode.label} profile. Switch '
                    'modes to edit a different profile.',
            children: [
              SettingRow(
                label: 'Top speed',
                icon: Icons.speed,
                currentValue: vehicle.gearTopSpeed != null
                    ? kmh(vehicle.gearTopSpeed!)
                    : '—',
                onTap: () => openEditor(
                  title: 'Gear top speed',
                  current: vehicle.gearTopSpeed,
                  min: 5,
                  max: 140,
                  step: 5,
                  format: kmh,
                  target: boardMcu,
                  register: regGearTopSpeed,
                  patch: (v) => ref
                      .read(vehicleProvider.notifier)
                      .patch(gearTopSpeed: v),
                ),
              ),
              SettingRow(
                label: 'Acceleration speed',
                icon: Icons.timer_outlined,
                currentValue: vehicle.gearAccSpeed != null
                    ? '${vehicle.gearAccSpeed}'
                    : '—',
                onTap: () => openEditor(
                  title: 'Acceleration speed',
                  current: vehicle.gearAccSpeed,
                  min: 0,
                  max: 100,
                  step: 5,
                  format: (v) => '$v',
                  target: boardMcu,
                  register: regGearAccSpeed,
                  patch: (v) => ref
                      .read(vehicleProvider.notifier)
                      .patch(gearAccSpeed: v),
                ),
              ),
              SettingRow(
                label: 'Acceleration sensitivity',
                icon: Icons.tune,
                currentValue: vehicle.gearAccSens != null
                    ? sens(vehicle.gearAccSens!)
                    : '—',
                onTap: () => openEditor(
                  title: 'Acceleration sensitivity',
                  current: vehicle.gearAccSens,
                  min: 0,
                  max: 2,
                  step: 1,
                  format: sens,
                  target: boardMcu,
                  register: regGearAccSens,
                  patch: (v) => ref
                      .read(vehicleProvider.notifier)
                      .patch(gearAccSens: v),
                ),
              ),
              SettingRow(
                label: 'Traction control',
                icon: Icons.compare_arrows,
                currentValue: vehicle.gearTcs != null
                    ? tcsLvl(vehicle.gearTcs!)
                    : '—',
                onTap: () => openEditor(
                  title: 'Gear traction control',
                  current: vehicle.gearTcs,
                  min: 0,
                  max: 2,
                  step: 1,
                  format: tcsLvl,
                  target: boardMcu,
                  register: regGearTcs,
                  patch: (v) =>
                      ref.read(vehicleProvider.notifier).patch(gearTcs: v),
                ),
              ),
              SettingRow(
                label: 'Nitro boost',
                icon: Icons.rocket_launch_outlined,
                currentValue: vehicle.gearNitro != null
                    ? onOff(vehicle.gearNitro!)
                    : '—',
                onTap: () => openEditor(
                  title: 'Nitro boost',
                  current: vehicle.gearNitro,
                  min: 0,
                  max: 1,
                  step: 1,
                  format: onOff,
                  target: boardMcu,
                  register: regGearNitro,
                  patch: (v) => ref
                      .read(vehicleProvider.notifier)
                      .patch(gearNitro: v),
                ),
              ),
              SettingRow(
                label: 'Energy level',
                icon: Icons.battery_charging_full_outlined,
                currentValue: vehicle.gearEnergy != null
                    ? '${vehicle.gearEnergy}'
                    : '—',
                onTap: () => openEditor(
                  title: 'Energy level',
                  description:
                      'Motor power profile. Higher values use more battery '
                      'for stronger acceleration.',
                  current: vehicle.gearEnergy,
                  min: 20,
                  max: 100,
                  step: 5,
                  format: (v) => '$v',
                  target: boardMcu,
                  register: regGearEnergy,
                  patch: (v) => ref
                      .read(vehicleProvider.notifier)
                      .patch(gearEnergy: v),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ModeTile extends StatelessWidget {
  final RidingMode mode;
  final bool selected;
  final VoidCallback onTap;

  const _ModeTile({
    required this.mode,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        child: Row(
          children: [
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_off,
              color: selected ? AppTheme.accent : AppTheme.textSecondary,
              size: 22,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(mode.label,
                      style: TextStyle(
                        color: selected
                            ? AppTheme.textPrimary
                            : AppTheme.textSecondary,
                        fontSize: 15,
                        fontWeight:
                            selected ? FontWeight.w600 : FontWeight.w400,
                      )),
                  Text(mode.hint,
                      style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 12,
                      )),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

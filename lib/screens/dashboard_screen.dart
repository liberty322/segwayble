/// Live telemetry dashboard screen.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/logger.dart';
import '../core/protocol/nb_protocol.dart';
import '../providers/connection_provider.dart';
import '../providers/demo_provider.dart';
import '../providers/gps_provider.dart';
import '../providers/session_provider.dart';
import '../providers/vehicle_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/battery_gauge.dart';
import '../widgets/connection_indicator.dart';
import '../widgets/speed_display.dart';
import '../widgets/stat_card.dart';
import 'device_info_screen.dart';
import 'raw_register_screen.dart';
import 'session_screen.dart';
import 'settings_screen.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  VehicleNotifier? _vehicleNotifier;

  @override
  void initState() {
    super.initState();
    talker.info('Screen[Dashboard] mounted');
    _vehicleNotifier = ref.read(vehicleProvider.notifier);
    _vehicleNotifier!.resumePolling(
      {PollTier.fast, PollTier.medium, PollTier.slow},
      by: 'Dashboard',
    );
  }

  @override
  void dispose() {
    talker.info('Screen[Dashboard] disposed');
    _vehicleNotifier?.pausePolling(by: 'Dashboard');
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final conn = ref.watch(connectionProvider);
    final vehicle = ref.watch(vehicleProvider);
    final isDemo = ref.watch(demoModeProvider);
    final gpsSpeed = ref.watch(gpsSpeedProvider);
    final recording = ref.watch(sessionRecordingProvider);

    final isRiding = vehicle.speed > 0 ||
        recording.state == RecordingState.recording;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ConnectionIndicator(connectionState: conn),
            if (isDemo) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppTheme.warning.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  'DEMO',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.warning,
                  ),
                ),
              ),
            ],
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: 'Ride History',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SessionScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const DeviceInfoScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'raw') {
                Navigator.of(context).push(
                  MaterialPageRoute(
                      builder: (_) => const RawRegisterScreen()),
                );
              } else if (v == 'exit_demo') {
                ref.read(demoModeProvider.notifier).state = false;
                Navigator.of(context).pop();
              } else if (v == 'disconnect') {
                ref.read(connectionProvider.notifier).disconnect();
                Navigator.of(context).pop();
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                  value: 'raw', child: Text('Raw Registers')),
              if (isDemo)
                const PopupMenuItem(
                    value: 'exit_demo', child: Text('Exit Demo'))
              else
                const PopupMenuItem(
                    value: 'disconnect', child: Text('Disconnect')),
            ],
          ),
        ],
      ),
      body: !conn.isConnected
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Connecting...',
                      style: TextStyle(color: AppTheme.textSecondary)),
                ],
              ),
            )
          : RefreshIndicator(
              onRefresh: () =>
                  ref.read(vehicleProvider.notifier).refresh(),
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    // Battery + Speed row
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        BatteryGauge(
                          percentage: vehicle.battery ?? 0,
                          size: 140,
                        ),
                        _SpeedWithGps(
                          bleSpeed: vehicle.speed,
                          gpsSpeed: gpsSpeed,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    // Power indicator
                    _PowerBar(
                      power: vehicle.power,
                      isPoweredOn: vehicle.isPoweredOn,
                    ),
                    const SizedBox(height: 16),

                    // Range
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppTheme.card,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.route,
                              color: AppTheme.primary, size: 20),
                          const SizedBox(width: 8),
                          Text(
                            '${vehicle.leftMileage.toStringAsFixed(1)} km remaining',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Conditional: vehicle actions (parked) or stats grid (riding)
                    if (isRiding)
                      _StatsGrid(vehicle: vehicle)
                    else
                      _VehicleActions(ref: ref, vehicle: vehicle),
                    const SizedBox(height: 16),

                    // Odometer
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppTheme.card,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Odometer',
                            style: TextStyle(
                              color: AppTheme.textSecondary,
                              fontSize: 14,
                            ),
                          ),
                          Text(
                            '${vehicle.mileage.toStringAsFixed(1)} km',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
      floatingActionButton: _RecordingFab(recording: recording, ref: ref),
    );
  }
}

// ---------------------------------------------------------------------------
// Stats grid (shown while riding)
// ---------------------------------------------------------------------------

class _StatsGrid extends StatelessWidget {
  final VehicleData vehicle;

  const _StatsGrid({required this.vehicle});

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: 1.6,
      children: [
        StatCard(
          label: 'Trip Distance',
          value: vehicle.singleMileage.toStringAsFixed(1),
          unit: 'km',
          icon: Icons.straighten,
        ),
        StatCard(
          label: 'Trip Time',
          value: vehicle.runningTimeFormatted,
          icon: Icons.timer,
        ),
        StatCard(
          label: 'Max Speed',
          value: vehicle.sigMaxSpeed.toStringAsFixed(1),
          unit: 'km/h',
          icon: Icons.speed,
        ),
        StatCard(
          label: 'Avg Speed',
          value: vehicle.aveSpeed.toStringAsFixed(1),
          unit: 'km/h',
          icon: Icons.trending_up,
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Vehicle actions card (shown while parked)
// ---------------------------------------------------------------------------

class _VehicleActions extends StatelessWidget {
  final WidgetRef ref;
  final VehicleData vehicle;

  const _VehicleActions({required this.ref, required this.vehicle});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Vehicle Controls',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppTheme.primary,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _VehicleActionButton(
                  icon: Icons.power_settings_new,
                  label: 'Power On',
                  color: AppTheme.success,
                  enabled: !vehicle.isPoweredOn,
                  onTap: () => _confirmAction(
                    context,
                    title: 'Power on vehicle?',
                    confirmLabel: 'Power On',
                    register: regOpenAcc,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _VehicleActionButton(
                  icon: Icons.power_off,
                  label: 'Power Off',
                  color: AppTheme.error,
                  enabled: vehicle.isPoweredOn,
                  onTap: () => _confirmAction(
                    context,
                    title: 'Power off vehicle?',
                    confirmLabel: 'Power Off',
                    register: regCloseAcc,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: _VehicleActionButton(
              icon: Icons.lock_open,
              label: 'Open Seat',
              color: AppTheme.primary,
              enabled: true, // VCU always online — works without power
              onTap: () => _confirmAction(
                context,
                title: 'Open seat compartment?',
                confirmLabel: 'Open',
                register: regOpenTrunk,
              ),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: _VehicleActionButton(
              icon: Icons.campaign,
              label: 'Honk & Flash',
              color: AppTheme.primary,
              enabled: true,
              onTap: () => _sendHonk(context),
            ),
          ),
        ],
      ),
    );
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

  void _confirmAction(
    BuildContext context, {
    required String title,
    required String confirmLabel,
    required int register,
  }) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _sendVehicleAction(context, register);
            },
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
  }

  void _sendVehicleAction(BuildContext context, int register) {
    final conn = ref.read(connectionProvider.notifier);
    final ident = conn.commandIdent;
    final regName = register == regOpenAcc
        ? 'openAcc'
        : register == regCloseAcc
            ? 'closeAcc'
            : register == regOpenTrunk
                ? 'openTrunk'
                : 'reg=0x${register.toRadixString(16)}';
    if (ident == null) {
      talker.warning('VehicleAction $regName aborted: no command ident');
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text(
            'No command ident — reconnect and paste {sn}_ident from your iOS backup.'),
        duration: Duration(seconds: 4),
      ));
      return;
    }

    final gen = conn.gen;
    final cfg = protoConfig[gen]!;
    final frame = buildFrame(cfg.vehicleTarget, cfg.vehicleCmd, register,
        data: ident, gen: gen);
    talker.info('VehicleAction $regName: sending frame (ident=${ident.length}B)');
    conn.sendOnly(frame);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Command sent'),
        duration: Duration(seconds: 2),
      ),
    );
  }
}

class _VehicleActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final bool enabled;
  final VoidCallback onTap;

  const _VehicleActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveColor = enabled ? color : AppTheme.textSecondary;
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: AnimatedOpacity(
        opacity: enabled ? 1.0 : 0.4,
        duration: const Duration(milliseconds: 200),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: effectiveColor.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: effectiveColor.withValues(alpha: 0.3),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: effectiveColor, size: 24),
              const SizedBox(height: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: effectiveColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Recording FAB
// ---------------------------------------------------------------------------

class _RecordingFab extends StatelessWidget {
  final SessionRecordingState recording;
  final WidgetRef ref;

  const _RecordingFab({required this.recording, required this.ref});

  @override
  Widget build(BuildContext context) {
    final isRecording = recording.state == RecordingState.recording;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (isRecording) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: AppTheme.error.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: AppTheme.error,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  'REC ${recording.elapsedFormatted}',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppTheme.error,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (recording.autoStarted) ...[
                  const SizedBox(width: 4),
                  const Text(
                    'AUTO',
                    style: TextStyle(
                      fontSize: 9,
                      color: AppTheme.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
        FloatingActionButton.small(
          backgroundColor: isRecording ? AppTheme.error : AppTheme.success,
          onPressed: () {
            if (isRecording) {
              ref.read(sessionRecordingProvider.notifier).stop();
            } else {
              ref.read(sessionRecordingProvider.notifier).start();
            }
          },
          child: Icon(
            isRecording ? Icons.stop : Icons.play_arrow,
            color: Colors.white,
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Supporting widgets
// ---------------------------------------------------------------------------

class _SpeedWithGps extends StatelessWidget {
  final double bleSpeed;
  final double? gpsSpeed;

  const _SpeedWithGps({required this.bleSpeed, this.gpsSpeed});

  @override
  Widget build(BuildContext context) {
    final delta = gpsSpeed != null ? (bleSpeed - gpsSpeed!).abs() : 0.0;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SpeedDisplay(speed: bleSpeed),
        if (gpsSpeed != null) ...[
          const SizedBox(height: 4),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.gps_fixed,
                  size: 12, color: AppTheme.textSecondary),
              const SizedBox(width: 4),
              Text(
                '${gpsSpeed!.toStringAsFixed(1)} km/h',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppTheme.textSecondary,
                ),
              ),
              if (delta > 1.0) ...[
                const SizedBox(width: 4),
                Icon(
                  bleSpeed > gpsSpeed!
                      ? Icons.arrow_upward
                      : Icons.arrow_downward,
                  size: 10,
                  color: AppTheme.warning,
                ),
                Text(
                  delta.toStringAsFixed(1),
                  style: const TextStyle(
                    fontSize: 10,
                    color: AppTheme.warning,
                  ),
                ),
              ],
            ],
          ),
        ],
      ],
    );
  }
}

class _PowerBar extends StatelessWidget {
  final int power;
  final bool isPoweredOn;

  const _PowerBar({required this.power, required this.isPoweredOn});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(
                isPoweredOn ? Icons.power : Icons.power_off,
                color: isPoweredOn ? AppTheme.success : AppTheme.textSecondary,
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                isPoweredOn ? 'ON' : 'OFF',
                style: TextStyle(
                  color:
                      isPoweredOn ? AppTheme.success : AppTheme.textSecondary,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          Text(
            '$power W',
            style: const TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

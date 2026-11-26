/// Snapshot of every known register, grouped and exportable as text.
///
/// Reads (or reuses cached reads via VehicleData) and renders a
/// human-readable table. A "Copy" / "Share" button exports the same
/// table so a second device or support ticket can receive it.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/logger.dart';
import '../../core/protocol/nb_protocol.dart';
import '../../providers/connection_provider.dart';
import '../../providers/vehicle_provider.dart';
import '../../theme/app_theme.dart';

/// One registry row.
@visibleForTesting
class RegEntry {
  final int target;
  final int register;
  final String label;
  final String Function(int raw) formatter;
  final int readLen;
  const RegEntry({
    required this.target,
    required this.register,
    required this.label,
    required this.formatter,
    this.readLen = 2,
  });
}

String _kmh(int v) => '$v km/h';
String _kmhTenth(int v) => '${(v / 10).toStringAsFixed(1)} km/h';
String _onOff(int v) => v == 0 ? 'Off' : 'On';
String _pct(int v) => '$v %';
String _bits(int v) =>
    '0x${v.toRadixString(16).padLeft(4, '0').toUpperCase()} '
    '(${v.toRadixString(2).padLeft(16, '0')})';
String _raw(int v) => '$v (0x${v.toRadixString(16).toUpperCase()})';
String _voltage(int v) => '${(v / 100).toStringAsFixed(2)} V';
String _seconds(int v) => '$v s';

@visibleForTesting
const configSnapshotGroups = _groups;

const _groups = <String, List<RegEntry>>{
  'Identity (DIS 0x01)': [
    RegEntry(
        target: boardDis,
        register: regSn,
        label: 'Serial number',
        readLen: 14,
        formatter: _raw),
    RegEntry(
        target: boardDis,
        register: regDisVersion,
        label: 'Dashboard fw',
        formatter: _raw),
    RegEntry(
        target: boardDis,
        register: regMcuVersion,
        label: 'MCU fw',
        formatter: _raw),
    RegEntry(
        target: boardDis,
        register: regEcuVersion,
        label: 'ECU fw',
        formatter: _raw),
    RegEntry(
        target: boardDis,
        register: regBms1Version,
        label: 'BMS1 fw',
        formatter: _raw),
  ],
  'Speed (DIS 0x01)': [
    RegEntry(
        target: boardDis,
        register: regLimitSpeed,
        label: 'Speed limit',
        formatter: _kmh),
    RegEntry(
        target: boardDis,
        register: regRatedSpeed,
        label: 'Rated max',
        formatter: _kmhTenth),
    RegEntry(
        target: boardDis,
        register: regSigMaxSpeed,
        label: 'Trip max',
        formatter: _kmhTenth),
  ],
  'Feature flags (DIS 0x01)': [
    RegEntry(
        target: boardDis,
        register: regFunBool,
        label: 'rFunBool',
        formatter: _bits),
    RegEntry(
        target: boardDis,
        register: regFunAppBool,
        label: 'rFunAppBool',
        formatter: _bits),
    RegEntry(
        target: boardDis,
        register: regCtlBool2,
        label: 'rCtlBool2',
        formatter: _bits),
    RegEntry(
        target: boardDis,
        register: regBool,
        label: 'rBool',
        formatter: _bits),
    RegEntry(
        target: boardDis,
        register: regBool2,
        label: 'rBool2 (modes)',
        formatter: _bits),
  ],
  'Vehicle state (DIS 0x01)': [
    RegEntry(
        target: boardDis,
        register: regBattery,
        label: 'Battery',
        formatter: _pct),
    RegEntry(
        target: boardDis,
        register: regLeftMileage,
        label: 'Remaining range',
        formatter: _kmhTenth),
    RegEntry(
        target: boardDis,
        register: regWarn,
        label: 'Sound preset',
        formatter: _raw),
    RegEntry(
        target: boardDis,
        register: regAlarmVolume,
        label: 'Alarm volume',
        formatter: _raw),
    RegEntry(
        target: boardDis,
        register: regAutoLock,
        label: 'Auto-lock',
        formatter: _seconds),
    RegEntry(
        target: boardDis,
        register: regAlarm,
        label: 'Alarm flags',
        formatter: _bits),
  ],
  'Traction & brake (MCU 0x20)': [
    RegEntry(
        target: boardMcu,
        register: regTcs,
        label: 'TCS global',
        formatter: _raw),
    RegEntry(
        target: boardMcu,
        register: regSlope,
        label: 'Slope assist',
        formatter: _raw),
    RegEntry(
        target: boardMcu,
        register: regEleBrake,
        label: 'Electric brake',
        formatter: _onOff),
    RegEntry(
        target: boardMcu,
        register: regSpeedIntensity,
        label: 'Speed intensity',
        formatter: _raw),
    RegEntry(
        target: boardMcu,
        register: regSpeedSafeLock,
        label: 'Speed safety lock',
        formatter: _raw),
  ],
  'Active gear profile (MCU 0x20)': [
    RegEntry(
        target: boardMcu,
        register: regGearTopSpeed,
        label: 'Top speed',
        formatter: _kmh),
    RegEntry(
        target: boardMcu,
        register: regGearAccSpeed,
        label: 'Acceleration speed',
        formatter: _raw),
    RegEntry(
        target: boardMcu,
        register: regGearAccSens,
        label: 'Acceleration sensitivity',
        formatter: _raw),
    RegEntry(
        target: boardMcu,
        register: regGearTcs,
        label: 'Gear TCS',
        formatter: _raw),
    RegEntry(
        target: boardMcu,
        register: regGearNitro,
        label: 'Nitro',
        formatter: _onOff),
    RegEntry(
        target: boardMcu,
        register: regGearEnergy,
        label: 'Energy level',
        formatter: _raw),
  ],
  'VCU (0x09)': [
    RegEntry(
        target: boardVcu,
        register: regMainPower,
        label: 'Main power state',
        formatter: _raw),
    RegEntry(
        target: boardVcu,
        register: regEcuPn,
        label: 'ECU part number',
        readLen: 14,
        formatter: _raw),
    RegEntry(
        target: boardVcu,
        register: regStateBool,
        label: 'State flags',
        formatter: _bits),
  ],
  'BMS1 (0x22)': [
    RegEntry(
        target: boardBms1,
        register: regVoltage,
        label: 'Voltage',
        formatter: _voltage),
    RegEntry(
        target: boardBms1,
        register: regBmsSoc,
        label: 'State of charge',
        formatter: _pct),
    RegEntry(
        target: boardBms1,
        register: regBmsCycleCount,
        label: 'Cycle count',
        formatter: _raw),
  ],
  'BLE (0x04)': [
    RegEntry(
        target: boardBle,
        register: regBleVersion,
        label: 'BLE fw',
        formatter: _raw),
  ],
};

/// Build a text-only export of a register snapshot.
///
/// [rawValues] keys are `"target_register"` (base-10) with u16/u32 raw
/// values. [asciiValues] keys use the same format and hold already-
/// decoded ASCII strings (for SN and ECU PN, which are read as bytes
/// but rendered as text).
String formatSnapshotText({
  required DateTime? capturedAt,
  required String? ecuPn,
  required Map<String, int?> rawValues,
  required Map<String, String?> asciiValues,
}) {
  String key(int t, int r) => '${t}_$r';
  final buf = StringBuffer();
  buf.writeln('# Segway configuration snapshot');
  buf.writeln('Captured: ${capturedAt?.toIso8601String() ?? '—'}');
  if (ecuPn != null) buf.writeln('ECU PN: $ecuPn');
  buf.writeln('');
  configSnapshotGroups.forEach((title, entries) {
    buf.writeln('## $title');
    for (final e in entries) {
      final k = key(e.target, e.register);
      final ascii = asciiValues[k];
      final raw = rawValues[k];
      final regHex = e.register.toRadixString(16).padLeft(2, '0');
      final tgtHex = e.target.toRadixString(16).padLeft(2, '0');
      final location = '[0x$tgtHex:0x$regHex]';
      final String valueText;
      if (ascii != null) {
        valueText = '"${ascii.replaceAll('\n', '\\n').replaceAll('\x00', '')}"';
      } else if (raw != null) {
        valueText = e.formatter(raw);
      } else {
        valueText = '—';
      }
      buf.writeln('  $location  ${e.label.padRight(28)} $valueText');
    }
    buf.writeln('');
  });
  return buf.toString();
}

class ConfigSnapshotScreen extends ConsumerStatefulWidget {
  const ConfigSnapshotScreen({super.key});

  @override
  ConsumerState<ConfigSnapshotScreen> createState() =>
      _ConfigSnapshotScreenState();
}

class _ConfigSnapshotScreenState extends ConsumerState<ConfigSnapshotScreen> {
  /// Keys as "${target}_${register}".
  final Map<String, int?> _values = {};
  final Map<String, String?> _asciiValues = {};
  bool _loading = false;
  DateTime? _lastRefreshed;

  // Progress state for the blocking overlay.
  int _progressDone = 0;
  int _progressTotal = 0;
  String _progressLabel = '';
  bool _progressAborted = false;

  @override
  void initState() {
    super.initState();
    talker.info('Screen[ConfigSnapshot] mounted');
    // The snapshot reads every register once on its own — it doesn't
    // need VehicleNotifier's timers and explicitly doesn't opt in for
    // them so the background pollers don't fight the snapshot for the
    // BLE mutex.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _refresh();
    });
  }

  @override
  void dispose() {
    talker.info('Screen[ConfigSnapshot] disposed');
    super.dispose();
  }

  String _key(int t, int r) => '${t}_$r';


  /// Boards that sleep when the vehicle is powered off. Skipping them
  /// saves roughly `(timeout × N)` seconds per snapshot pass.
  static const _asleepBoards = <int>{
    0x20 /* MCU */,
    0x22 /* BMS1 */, 0x23 /* BMS2 */,
    0x25 /* ECU */,
  };

  Future<void> _refresh() async {
    if (_loading) return;
    final vehicle = ref.read(vehicleProvider);
    final poweredOn = vehicle.isPoweredOn;
    // Pre-compute how many reads we're actually going to run so the
    // progress bar shows an accurate denominator.
    final plannedReads = _groups.values.fold<int>(0, (sum, group) {
      return sum +
          group
              .where((e) => poweredOn || !_asleepBoards.contains(e.target))
              .length;
    });
    setState(() {
      _loading = true;
      _progressDone = 0;
      _progressTotal = plannedReads;
      _progressLabel = 'Preparing…';
      _progressAborted = false;
    });
    talker.info('Snapshot refresh START: $plannedReads reads '
        '(poweredOn=$poweredOn)');
    final conn = ref.read(connectionProvider.notifier);
    // Short per-op timeout: a healthy BLE read completes in <150 ms;
    // anything longer is almost certainly a link drop or a register
    // the device has no handler for. Bail fast so the snapshot doesn't
    // hang behind a reconnect cascade.
    const perReadTimeout = Duration(milliseconds: 1200);
    var aborted = false;
    for (final group in _groups.values) {
      if (aborted) break;
      for (final entry in group) {
        if (!ref.read(connectionProvider).isConnected) {
          aborted = true;
          break;
        }
        // Vehicle off → skip asleep boards. Leaves the values as "—"
        // in the UI (they were never populated) but keeps the snapshot
        // fast (no 2 s timeout per dead read).
        if (!poweredOn && _asleepBoards.contains(entry.target)) {
          continue;
        }
        if (mounted) {
          setState(() => _progressLabel = entry.label);
        }
        final t0 = DateTime.now();
        try {
          if (entry.readLen > 4) {
            final f = await conn.readRegister(entry.target, entry.register,
                readLen: entry.readLen, timeout: perReadTimeout);
            if (!mounted) return;
            _asciiValues[_key(entry.target, entry.register)] =
                f?.readAscii(entry.readLen);
          } else if (entry.readLen == 4) {
            final v = await conn.readU32(entry.target, entry.register,
                timeout: perReadTimeout);
            if (!mounted) return;
            _values[_key(entry.target, entry.register)] = v;
          } else {
            final v = await conn.readU16(entry.target, entry.register,
                timeout: perReadTimeout);
            if (!mounted) return;
            _values[_key(entry.target, entry.register)] = v;
          }
        } catch (_) {
          // leave unset — renders as "—"
        }
        final elapsed = DateTime.now().difference(t0).inMilliseconds;
        if (elapsed > 200) {
          talker.warning('Snapshot slow read: ${entry.label} took ${elapsed}ms');
        }
        if (!mounted) return;
        setState(() => _progressDone++);
      }
    }
    if (!mounted) return;
    setState(() {
      _loading = false;
      _progressAborted = aborted;
      if (!aborted) _lastRefreshed = DateTime.now();
    });
    talker.info('Snapshot refresh END: done=$_progressDone/$_progressTotal '
        'aborted=$aborted');
  }

  String _exportText() => formatSnapshotText(
        capturedAt: _lastRefreshed,
        ecuPn: ref.read(vehicleProvider).ecuPn,
        rawValues: _values,
        asciiValues: _asciiValues,
      );

  Future<void> _copyToClipboard() async {
    await Clipboard.setData(ClipboardData(text: _exportText()));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Snapshot copied to clipboard'),
      duration: Duration(seconds: 2),
    ));
  }

  Future<void> _shareText() async {
    await SharePlus.instance.share(
      ShareParams(text: _exportText(), subject: 'Segway config snapshot'),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Block back-press while reads are inflight so we can't leave a
      // wedge of queued frames behind.
      canPop: !_loading,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Current configuration'),
          actions: [
            IconButton(
              tooltip: 'Refresh',
              onPressed: _loading ? null : _refresh,
              icon: const Icon(Icons.refresh),
            ),
            IconButton(
              tooltip: 'Copy',
              onPressed: _loading ? null : _copyToClipboard,
              icon: const Icon(Icons.copy_all_outlined),
            ),
            IconButton(
              tooltip: 'Share',
              onPressed: _loading ? null : _shareText,
              icon: const Icon(Icons.share_outlined),
            ),
          ],
        ),
        body: Stack(
          children: [
            ListView(
              padding: const EdgeInsets.symmetric(vertical: 12),
              children: [
                if (_lastRefreshed != null)
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                    child: Text(
                      'Captured ${_timeAgo(_lastRefreshed!)}',
                      style: const TextStyle(
                          color: AppTheme.textSecondary, fontSize: 12),
                    ),
                  ),
                ..._groups.entries.map(_buildGroup),
              ],
            ),
            if (_loading) _buildProgressOverlay(),
            if (_progressAborted && !_loading) _buildAbortedBanner(),
          ],
        ),
      ),
    );
  }

  Widget _buildProgressOverlay() {
    final total = _progressTotal == 0 ? 1 : _progressTotal;
    final fraction = (_progressDone / total).clamp(0.0, 1.0);
    return Positioned.fill(
      child: AbsorbPointer(
        child: Container(
          color: Colors.black.withValues(alpha: 0.78),
          alignment: Alignment.center,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 32),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.primary.withValues(alpha: 0.4)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Reading registers',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppTheme.primary,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  _progressLabel,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 20),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: fraction,
                    minHeight: 10,
                    backgroundColor: AppTheme.card,
                    valueColor: const AlwaysStoppedAnimation<Color>(
                        AppTheme.accent),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '$_progressDone / $_progressTotal  '
                  '(${(fraction * 100).toStringAsFixed(0)}%)',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 12,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'BLE is busy — please wait',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 11,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAbortedBanner() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        color: AppTheme.warning.withValues(alpha: 0.15),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        child: const Row(
          children: [
            Icon(Icons.warning_amber_rounded,
                color: AppTheme.warning, size: 18),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Snapshot aborted — connection dropped mid-read. '
                'Reconnect and try again.',
                style: TextStyle(color: AppTheme.textPrimary, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGroup(MapEntry<String, List<RegEntry>> entry) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
            child: Text(
              entry.key.toUpperCase(),
              style: const TextStyle(
                color: AppTheme.primary,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
              ),
            ),
          ),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: AppTheme.card,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(children: [
              for (var i = 0; i < entry.value.length; i++) ...[
                _buildRow(entry.value[i]),
                if (i < entry.value.length - 1)
                  const Divider(
                      height: 1, thickness: 1, color: AppTheme.surface),
              ],
            ]),
          ),
        ],
      ),
    );
  }

  Widget _buildRow(RegEntry e) {
    final k = _key(e.target, e.register);
    final ascii = _asciiValues[k];
    final raw = _values[k];
    final String value;
    if (ascii != null) {
      value = '"${ascii.replaceAll('\x00', '').trim()}"';
    } else if (raw != null) {
      value = e.formatter(raw);
    } else {
      value = '—';
    }
    final regHex = e.register.toRadixString(16).padLeft(2, '0').toUpperCase();
    final tgtHex = e.target.toRadixString(16).padLeft(2, '0').toUpperCase();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(e.label,
                    style: const TextStyle(
                        color: AppTheme.textPrimary, fontSize: 14)),
                Text('0x$tgtHex:0x$regHex',
                    style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 11,
                        fontFamily: 'monospace')),
              ],
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              color: AppTheme.accent,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }

  static String _timeAgo(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inSeconds < 5) return 'just now';
    if (d.inSeconds < 60) return '${d.inSeconds}s ago';
    if (d.inMinutes < 60) return '${d.inMinutes}m ago';
    return '${d.inHours}h ago';
  }
}

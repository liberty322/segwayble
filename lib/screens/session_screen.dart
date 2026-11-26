/// Session history and detail screens.
library;

import 'dart:io';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../data/ride_session.dart';
import '../data/session_db.dart';
import '../providers/session_provider.dart';
import '../theme/app_theme.dart';

class SessionScreen extends ConsumerWidget {
  const SessionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessions = ref.watch(sessionListProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Ride History')),
      body: sessions.when(
        data: (list) {
          if (list.isEmpty) {
            return const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.directions_bike,
                      size: 64, color: AppTheme.textSecondary),
                  SizedBox(height: 16),
                  Text('No rides recorded yet',
                      style: TextStyle(color: AppTheme.textSecondary)),
                  SizedBox(height: 8),
                  Text('Rides are recorded automatically when you ride',
                      style: TextStyle(
                          color: AppTheme.textSecondary, fontSize: 12)),
                ],
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: list.length,
            itemBuilder: (context, index) {
              final session = list[index];
              return _SessionTile(
                session: session,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => _SessionDetailScreen(session: session),
                  ),
                ),
                onDelete: () => _confirmDelete(context, ref, session),
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
    );
  }

  void _confirmDelete(
      BuildContext context, WidgetRef ref, RideSession session) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Ride?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              if (session.id != null) {
                await SessionDatabase().deleteSession(session.id!);
                ref.invalidate(sessionListProvider);
              }
            },
            child: const Text('Delete',
                style: TextStyle(color: AppTheme.error)),
          ),
        ],
      ),
    );
  }
}

class _SessionTile extends StatelessWidget {
  final RideSession session;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _SessionTile({
    required this.session,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final date = _formatDate(session.startTime);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: const Icon(Icons.route, color: AppTheme.primary),
        title: Text(date),
        subtitle: Text(
          '${session.distance.toStringAsFixed(2)} km  ·  '
          '${session.durationFormatted}  ·  '
          '${session.maxBleSpeed.toStringAsFixed(1)} km/h max',
          style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
        ),
        trailing: IconButton(
          icon: const Icon(Icons.delete_outline,
              size: 20, color: AppTheme.textSecondary),
          onPressed: onDelete,
        ),
        onTap: onTap,
      ),
    );
  }

  static const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];

  String _formatDate(DateTime dt) {
    final wd = _weekdays[dt.weekday - 1];
    final mo = _months[dt.month - 1];
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$wd ${dt.day} $mo, $h:$m';
  }
}

class _SessionDetailScreen extends StatefulWidget {
  final RideSession session;

  const _SessionDetailScreen({required this.session});

  @override
  State<_SessionDetailScreen> createState() => _SessionDetailScreenState();
}

class _SessionDetailScreenState extends State<_SessionDetailScreen> {
  List<TelemetryPoint>? _telemetry;
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    _loadTelemetry();
  }

  Future<void> _loadTelemetry() async {
    if (widget.session.id == null) return;
    final points = await SessionDatabase().getTelemetry(widget.session.id!);
    if (mounted) setState(() => _telemetry = points);
  }

  Future<void> _exportCsv() async {
    if (_telemetry == null || _telemetry!.isEmpty) return;
    setState(() => _exporting = true);

    try {
      final buf = StringBuffer();
      buf.writeln('timestamp,ble_speed_kmh,gps_speed_kmh,power_w,battery_pct,lat,lng');
      for (final p in _telemetry!) {
        buf.writeln(
          '${p.timestamp.toIso8601String()},'
          '${p.bleSpeed.toStringAsFixed(1)},'
          '${p.gpsSpeed?.toStringAsFixed(1) ?? ""},'
          '${p.power},'
          '${p.battery},'
          '${p.lat?.toStringAsFixed(6) ?? ""},'
          '${p.lng?.toStringAsFixed(6) ?? ""}',
        );
      }

      final dir = await getTemporaryDirectory();
      final dateStr = widget.session.startTime
          .toIso8601String()
          .replaceAll(':', '-')
          .split('.')
          .first;
      final file = File('${dir.path}/ride_$dateStr.csv');
      await file.writeAsString(buf.toString());

      await SharePlus.instance.share(
        ShareParams(files: [XFile(file.path)]),
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final hasData = _telemetry != null && _telemetry!.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ride Details'),
        actions: [
          if (hasData)
            IconButton(
              icon: _exporting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.share),
              tooltip: 'Export CSV',
              onPressed: _exporting ? null : _exportCsv,
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _StatRow('Duration', session.durationFormatted),
            _StatRow('Distance', '${session.distance.toStringAsFixed(2)} km'),
            _StatRow('Max BLE Speed',
                '${session.maxBleSpeed.toStringAsFixed(1)} km/h'),
            _StatRow('Max GPS Speed',
                '${session.maxGpsSpeed.toStringAsFixed(1)} km/h'),
            _StatRow('Avg Speed',
                '${session.avgBleSpeed.toStringAsFixed(1)} km/h'),
            if (session.accel0to45Time != null)
              _StatRow('0-45 km/h',
                  '${session.accel0to45Time!.toStringAsFixed(1)} s'),
            const SizedBox(height: 16),

            // Speed chart
            if (hasData) ...[
              const Text(
                'Speed',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.primary,
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 200,
                child: _SpeedChart(
                  telemetry: _telemetry!,
                  sessionStart: session.startTime,
                ),
              ),
              const SizedBox(height: 16),
            ],

            Text(
              'Started: ${session.startTime.toLocal()}',
              style: const TextStyle(
                  fontSize: 12, color: AppTheme.textSecondary),
            ),
            if (session.endTime != null)
              Text(
                'Ended: ${session.endTime!.toLocal()}',
                style: const TextStyle(
                    fontSize: 12, color: AppTheme.textSecondary),
              ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Speed chart
// ---------------------------------------------------------------------------

class _SpeedChart extends StatelessWidget {
  final List<TelemetryPoint> telemetry;
  final DateTime sessionStart;

  const _SpeedChart({required this.telemetry, required this.sessionStart});

  @override
  Widget build(BuildContext context) {
    final bleSpots = <FlSpot>[];
    final gpsSpots = <FlSpot>[];
    double maxSpeed = 10;

    for (final p in telemetry) {
      final t = p.timestamp.difference(sessionStart).inMilliseconds / 1000.0;
      bleSpots.add(FlSpot(t, p.bleSpeed));
      if (p.bleSpeed > maxSpeed) maxSpeed = p.bleSpeed;
      if (p.gpsSpeed != null) {
        gpsSpots.add(FlSpot(t, p.gpsSpeed!));
        if (p.gpsSpeed! > maxSpeed) maxSpeed = p.gpsSpeed!;
      }
    }

    final maxX = bleSpots.isNotEmpty ? bleSpots.last.x : 60.0;
    final maxY = (maxSpeed * 1.1).ceilToDouble();

    return Container(
      padding: const EdgeInsets.only(right: 8, top: 8),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(12),
      ),
      child: LineChart(
        LineChartData(
          minY: 0,
          maxY: maxY,
          minX: 0,
          maxX: maxX,
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: maxY > 40 ? 20 : 10,
            getDrawingHorizontalLine: (value) => FlLine(
              color: AppTheme.surface,
              strokeWidth: 0.5,
            ),
          ),
          titlesData: FlTitlesData(
            rightTitles: const AxisTitles(),
            topTitles: const AxisTitles(),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                interval: maxX > 300 ? 60 : (maxX > 60 ? 30 : 10),
                getTitlesWidget: (value, meta) {
                  final s = value.round();
                  final m = s ~/ 60;
                  final sec = s % 60;
                  return SideTitleWidget(
                    meta: meta,
                    child: Text(
                      m > 0 ? '${m}m' : '${sec}s',
                      style: const TextStyle(
                        fontSize: 10,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  );
                },
              ),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 36,
                interval: maxY > 40 ? 20 : 10,
                getTitlesWidget: (value, meta) => SideTitleWidget(
                  meta: meta,
                  child: Text(
                    '${value.round()}',
                    style: const TextStyle(
                      fontSize: 10,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ),
              ),
            ),
          ),
          borderData: FlBorderData(show: false),
          lineBarsData: [
            // BLE speed — primary cyan line
            LineChartBarData(
              spots: bleSpots,
              isCurved: true,
              curveSmoothness: 0.2,
              preventCurveOverShooting: true,
              color: AppTheme.accent,
              barWidth: 2,
              isStrokeCapRound: true,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                color: AppTheme.accent.withValues(alpha: 0.1),
              ),
            ),
            // GPS speed — grey dashed line
            if (gpsSpots.length > 1)
              LineChartBarData(
                spots: gpsSpots,
                isCurved: true,
                curveSmoothness: 0.2,
                preventCurveOverShooting: true,
                color: AppTheme.textSecondary.withValues(alpha: 0.6),
                barWidth: 1.5,
                isStrokeCapRound: true,
                dashArray: [4, 4],
                dotData: const FlDotData(show: false),
              ),
          ],
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (_) => AppTheme.surface,
              getTooltipItems: (spots) => spots.map((spot) {
                final isBle = spot.barIndex == 0;
                return LineTooltipItem(
                  '${spot.y.toStringAsFixed(1)} km/h',
                  TextStyle(
                    color: isBle ? AppTheme.accent : AppTheme.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                );
              }).toList(),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Supporting widgets
// ---------------------------------------------------------------------------

class _StatRow extends StatelessWidget {
  final String label;
  final String value;

  const _StatRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: const TextStyle(
                  color: AppTheme.textSecondary, fontSize: 14)),
          Text(value,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}

/// Device information screen — serial, firmware versions, config info.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/protocol/nb_protocol.dart';
import '../providers/connection_provider.dart';
import '../providers/device_config_provider.dart';
import '../theme/app_theme.dart';

class DeviceInfoScreen extends ConsumerStatefulWidget {
  const DeviceInfoScreen({super.key});

  @override
  ConsumerState<DeviceInfoScreen> createState() => _DeviceInfoScreenState();
}

class _DeviceInfoScreenState extends ConsumerState<DeviceInfoScreen> {
  String? _sn;
  String? _ecuPn;
  String? _disVersion;
  String? _mcuVersion;
  String? _bleVersion;
  String? _ecuVersion;
  String? _bmsVersion;
  int? _voltage;
  int? _cycles;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadInfo();
  }

  String _fmtVersion(int? v) {
    if (v == null) return '?';
    return '${(v >> 8) & 0xFF}.${(v >> 4) & 0xF}.${v & 0xF}';
  }

  Future<void> _loadInfo() async {
    final conn = ref.read(connectionProvider.notifier);

    try {
      // Read serial number
      final snResp = await conn.readRegister(boardDis, regSn, readLen: 14);
      if (snResp != null) {
        _sn = snResp.readAscii(14);
      }

      // ECU PN
      final ecuResp = await conn.readRegister(boardVcu, regEcuPn, readLen: 14);
      if (ecuResp != null) {
        _ecuPn = ecuResp.readAscii(14);
      }

      // Versions
      final disV = await conn.readU16(boardDis, regDisVersion);
      final mcuV = await conn.readU16(boardDis, regMcuVersion);
      final bleV = await conn.readU16(boardBle, regBleVersion);
      final ecuV = await conn.readU16(boardDis, regEcuVersion);
      final bmsV = await conn.readU16(boardDis, regBms1Version);

      // BMS
      final voltage = await conn.readU16(boardBms1, regVoltage);
      final cycles = await conn.readU16(boardBms1, regBmsCycleCount);

      if (mounted) {
        setState(() {
          _disVersion = _fmtVersion(disV);
          _mcuVersion = _fmtVersion(mcuV);
          _bleVersion = _fmtVersion(bleV);
          _ecuVersion = _fmtVersion(ecuV);
          _bmsVersion = _fmtVersion(bmsV);
          _voltage = voltage;
          _cycles = cycles;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final conn = ref.watch(connectionProvider);
    final configAsync = ref.watch(activeDeviceConfigProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Device Info')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _InfoCard(title: 'Vehicle', items: [
                  _InfoRow('Serial Number', _sn ?? conn.serialNumber ?? '?'),
                  _InfoRow('Device Name', conn.deviceName ?? '?'),
                  _InfoRow('ECU PN', _ecuPn ?? '?'),
                ]),
                const SizedBox(height: 12),
                _InfoCard(title: 'Firmware Versions', items: [
                  _InfoRow('Display (DIS)', _disVersion ?? '?'),
                  _InfoRow('MCU', _mcuVersion ?? '?'),
                  _InfoRow('BLE', _bleVersion ?? '?'),
                  _InfoRow('ECU', _ecuVersion ?? '?'),
                  _InfoRow('BMS', _bmsVersion ?? '?'),
                ]),
                const SizedBox(height: 12),
                _InfoCard(title: 'Battery', items: [
                  _InfoRow('Voltage',
                      _voltage != null ? '${(_voltage! * 0.01).toStringAsFixed(2)} V' : '?'),
                  _InfoRow('Charge Cycles', _cycles?.toString() ?? '?'),
                ]),
                const SizedBox(height: 12),
                configAsync.when(
                  data: (config) => config != null
                      ? _InfoCard(title: 'Device Config', items: [
                          _InfoRow('Server ID', '${config.serverId}'),
                          _InfoRow('Name', config.name),
                          _InfoRow('Model', config.model),
                          _InfoRow('Hardware ID', config.hardwareId),
                          _InfoRow('Commands', '${config.commands.length}'),
                        ])
                      : const SizedBox.shrink(),
                  loading: () => const CircularProgressIndicator(),
                  error: (e, st) => const SizedBox.shrink(),
                ),
              ],
            ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final String title;
  final List<_InfoRow> items;

  const _InfoCard({required this.title, required this.items});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppTheme.primary,
            ),
          ),
          const SizedBox(height: 12),
          ...items,
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              color: AppTheme.textSecondary,
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 13,
              fontFamily: 'monospace',
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

/// Advanced settings — config mode, debug, raw command, diagnostic export.
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:talker_flutter/talker_flutter.dart';

import '../../core/logger.dart' show talker, isVerboseLogging, setVerboseLogging;
import '../../core/protocol/nb_protocol.dart';
import '../../providers/connection_provider.dart';
import '../../providers/vehicle_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/setting_row.dart';
import '../../widgets/value_editor.dart';
import '../raw_register_screen.dart';

final _verboseLoggingProvider = StateProvider<bool>((ref) => isVerboseLogging);

class AdvancedScreen extends ConsumerWidget {
  const AdvancedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vehicle = ref.watch(vehicleProvider);
    final conn = ref.read(connectionProvider.notifier);
    final verbose = ref.watch(_verboseLoggingProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Advanced')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 16),
        children: [
          SettingSection(
            title: 'Device',
            children: [
              SettingRow(
                label: 'Config mode',
                subtitle: 'Value depends on device — KPH/MPH or profile',
                icon: Icons.settings_input_component,
                currentValue: vehicle.warn != null ? null : null,
                onTap: () {
                  Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => ValueEditor(
                      title: 'Config mode (raw)',
                      description:
                          'Raw u16 write to DIS 0x74. 0 = metric, 1 = imperial '
                          'on most firmwares but the meaning is device-specific.',
                      current: 0,
                      min: 0,
                      max: 10,
                      step: 1,
                      format: (v) => '$v',
                      onSave: (v) =>
                          conn.writeAndVerifyU16(boardDis, regCfgMode, v),
                    ),
                  ));
                },
              ),
              SettingRow(
                label: 'Raw command',
                subtitle: 'Hand-craft a register read/write',
                icon: Icons.terminal,
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const RawRegisterScreen(),
                )),
              ),
              SettingRow(
                label: 'Speed unlock (raw)',
                subtitle: 'Bypass crypto — 13-byte magic frame',
                icon: Icons.flash_on,
                onTap: () => _confirmAndSendRawSpeedUnlock(context, conn),
              ),
            ],
          ),
          SettingSection(
            title: 'Debug',
            children: [
              Material(
                color: Colors.transparent,
                child: SwitchListTile(
                  title: const Text('Verbose BLE logging',
                      style: TextStyle(color: Colors.white)),
                  subtitle: const Text(
                      'Hex dump every frame; view in "App logs" below',
                      style: TextStyle(fontSize: 12)),
                  secondary: const Icon(Icons.bug_report_outlined),
                  value: verbose,
                  onChanged: (v) {
                    ref.read(_verboseLoggingProvider.notifier).state = v;
                    setVerboseLogging(v);
                  },
                ),
              ),
              SettingRow(
                label: 'App logs',
                icon: Icons.article_outlined,
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => TalkerScreen(talker: talker),
                )),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// The "magic" speed-unlock frame from the old settings screen. This
  /// bypasses every protection — no encryption, no MAC, no handshake —
  /// and goes straight out via `sendRaw`. Exact origin of the payload
  /// is lost in the CTF scratch notes, but it flips the speed limit
  /// back to stock on devices that refuse the normal WRITE_NR path.
  Future<void> _confirmAndSendRawSpeedUnlock(
      BuildContext context, ConnectionNotifier conn) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text('Send speed unlock frame?',
            style: TextStyle(color: Colors.white)),
        content: const Text(
          "This sends a hardcoded 13-byte frame UNENCRYPTED and "
          "UNSEQUENCED via sendRaw(). It bypasses the BLE mutex, the "
          "crypto, and session state. Use only if you know what you're "
          "doing.",
          style: TextStyle(color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Send',
                style: TextStyle(color: AppTheme.error)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final raw = Uint8List.fromList([
      0x5a, 0xa5, 0x00, 0x70, 0x57, 0x45, 0x66, 0x51,
      0x12, 0x23, 0x14, 0x7a, 0x39,
    ]);
    await conn.sendRaw(raw);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Speed unlock frame sent'),
        duration: Duration(seconds: 2),
      ));
    }
  }
}

/// BLE scanner screen with saved devices and scan results.
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/ble/ble_scanner.dart';
import '../core/protocol/nb_protocol.dart';
import '../data/credential_qr.dart';
import '../data/saved_device.dart';
import '../providers/ble_provider.dart';
import '../providers/connection_provider.dart';
import '../providers/demo_provider.dart';
import '../providers/device_config_provider.dart';
import '../providers/saved_devices_provider.dart';
import '../theme/app_theme.dart';
import 'dashboard_screen.dart';
import 'qr_scanner_screen.dart';

class ScanScreen extends ConsumerStatefulWidget {
  const ScanScreen({super.key});

  @override
  ConsumerState<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends ConsumerState<ScanScreen> {
  @override
  Widget build(BuildContext context) {
    final scanned = ref.watch(scannedDevicesProvider);
    final isScanning = ref.watch(isScanningProvider);
    final connState = ref.watch(connectionProvider);
    final adapterState = ref.watch(bleAdapterStateProvider);
    final savedAsync = ref.watch(savedDevicesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Segway BLE'),
        actions: [
          IconButton(
            icon: const Icon(Icons.play_circle_outline),
            tooltip: 'Demo Mode',
            onPressed: () {
              ref.read(demoModeProvider.notifier).state = true;
              _goToDashboard(context);
            },
          ),
          if (connState.isConnected)
            IconButton(
              icon: const Icon(Icons.dashboard, color: AppTheme.primary),
              onPressed: () => _goToDashboard(context),
            ),
        ],
      ),
      body: adapterState.when(
        data: (state) {
          if (state != BluetoothAdapterState.on) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.bluetooth_disabled,
                      size: 64, color: AppTheme.textSecondary),
                  const SizedBox(height: 16),
                  Text(
                    state == BluetoothAdapterState.unavailable
                        ? 'Bluetooth unavailable\n(Simulator has no BLE hardware)'
                        : 'Bluetooth is off',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppTheme.textSecondary),
                  ),
                ],
              ),
            );
          }
          final saved = savedAsync.value ?? [];
          return _buildBody(saved, scanned, isScanning, connState);
        },
        loading: () => const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.bluetooth_searching,
                  size: 64, color: AppTheme.textSecondary),
              SizedBox(height: 16),
              Text('Waiting for Bluetooth adapter...',
                  style: TextStyle(color: AppTheme.textSecondary)),
              SizedBox(height: 8),
              Text(
                'If on Simulator: BLE is not supported.\nUse a real device to scan.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
              ),
            ],
          ),
        ),
        error: (e, st) =>
            const Center(child: Text('Bluetooth unavailable')),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: isScanning
            ? () => ref.read(scannedDevicesProvider.notifier).stopScan()
            : () => ref.read(scannedDevicesProvider.notifier).startScan(),
        backgroundColor: AppTheme.primary,
        child: Icon(
          isScanning ? Icons.stop : Icons.bluetooth_searching,
          color: Colors.black,
        ),
      ),
    );
  }

  Widget _buildBody(
    List<SavedDevice> saved,
    List<ScannedDevice> scanned,
    bool isScanning,
    BleConnectionState connState,
  ) {
    final scannedByMac = {for (final d in scanned) d.id: d};
    final savedMacs = {for (final s in saved) s.mac};
    final nearby = scanned.where((d) => !savedMacs.contains(d.id)).toList();

    final isConnecting = connState.phase == ConnectionPhase.connecting ||
        connState.phase == ConnectionPhase.handshaking;

    if (saved.isEmpty && nearby.isEmpty && !isScanning) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off, size: 64, color: AppTheme.textSecondary),
            SizedBox(height: 16),
            Text('No devices found',
                style: TextStyle(color: AppTheme.textSecondary)),
            SizedBox(height: 8),
            Text('Tap the scan button to search',
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // -- My Devices --
        if (saved.isNotEmpty) ...[
          const _SectionHeader(title: 'My Devices'),
          const SizedBox(height: 8),
          for (final device in saved)
            _SavedDeviceTile(
              device: device,
              scannedDevice: scannedByMac[device.mac],
              isConnecting: isConnecting,
              onTap: () => _connectSaved(device, scannedByMac[device.mac]),
              onLongPress: () => _confirmForget(device),
            ),
          const SizedBox(height: 16),
        ],

        // -- Nearby Devices --
        if (nearby.isNotEmpty || isScanning) ...[
          const _SectionHeader(title: 'Nearby Devices'),
          const SizedBox(height: 8),
          for (final device in nearby)
            _DeviceTile(
              device: device,
              onTap: () => _connectToDevice(device),
              isConnecting: isConnecting,
            ),
          if (isScanning)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            ),
        ],
      ],
    );
  }

  Future<void> _connectSaved(
      SavedDevice saved, ScannedDevice? scannedDevice) async {
    final device =
        scannedDevice?.device ?? BluetoothDevice.fromId(saved.mac);
    final name = scannedDevice?.name ?? saved.name;

    // Auto-match device type
    final registry = await ref.read(deviceRegistryProvider.future);
    final entry = registry.matchDevice(name);
    if (entry != null) {
      ref.read(activeDeviceEntryProvider.notifier).state = entry;
    }

    if (!mounted) return;

    _showConnectionDialog();

    ref.read(connectionProvider.notifier).connect(
          device,
          btName: name,
          gen: ProtocolGen.gen2,
          storedPassword: saved.password,
        );
  }

  Future<void> _connectToDevice(ScannedDevice device) async {
    _showConnectOptions(device);
  }

  void _showConnectOptions(ScannedDevice device) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  device.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              ListTile(
                leading:
                    const Icon(Icons.add_link, color: AppTheme.primary),
                title: const Text('New pairing',
                    style: TextStyle(color: Colors.white)),
                subtitle: const Text(
                  'Pair as new device (press button when prompted)',
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                ),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _connectNewPairing(device);
                },
              ),
              ListTile(
                leading: const Icon(Icons.key, color: AppTheme.primary),
                title: const Text('Connect with password',
                    style: TextStyle(color: Colors.white)),
                subtitle: const Text(
                  'Use a stored password from an iOS backup',
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                ),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _showPasswordImport(device);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _connectNewPairing(ScannedDevice device) async {
    // Auto-match device type
    final registry = await ref.read(deviceRegistryProvider.future);
    final entry = registry.matchDevice(device.name);
    if (entry != null) {
      ref.read(activeDeviceEntryProvider.notifier).state = entry;
    }

    if (!mounted) return;

    _showConnectionDialog();

    ref.read(connectionProvider.notifier).connect(
          device.device,
          btName: device.name,
          gen: ProtocolGen.gen2,
        );
  }

  void _showPasswordImport(ScannedDevice device) {
    showDialog(
      context: context,
      builder: (ctx) => _PasswordImportDialog(
        onSubmit: (password, commandIdent) async {
          // Auto-match device type
          final registry = await ref.read(deviceRegistryProvider.future);
          final entry = registry.matchDevice(device.name);
          if (entry != null) {
            ref.read(activeDeviceEntryProvider.notifier).state = entry;
          }

          if (!mounted) return;

          _showConnectionDialog();

          ref.read(connectionProvider.notifier).connect(
                device.device,
                btName: device.name,
                gen: ProtocolGen.gen2,
                storedPassword: password,
                commandIdent: commandIdent,
              );
        },
      ),
    );
  }

  void _showConnectionDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ConnectionProgressDialog(
        onConnected: () => _goToDashboard(context),
        onCancel: () => ref.read(connectionProvider.notifier).disconnect(),
      ),
    );
  }

  void _confirmForget(SavedDevice device) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title:
            const Text('Forget Device', style: TextStyle(color: Colors.white)),
        content: Text(
          'Remove "${device.name}" and its stored password?',
          style: const TextStyle(color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              ref.read(savedDevicesProvider.notifier).removeDevice(device.mac);
              Navigator.of(ctx).pop();
            },
            child:
                const Text('Forget', style: TextStyle(color: AppTheme.error)),
          ),
        ],
      ),
    );
  }

  void _goToDashboard(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const DashboardScreen()),
    );
  }
}

// ---------------------------------------------------------------------------
// Widgets
// ---------------------------------------------------------------------------

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: AppTheme.textSecondary,
        letterSpacing: 0.5,
      ),
    );
  }
}

class _SavedDeviceTile extends StatelessWidget {
  final SavedDevice device;
  final ScannedDevice? scannedDevice;
  final bool isConnecting;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _SavedDeviceTile({
    required this.device,
    required this.scannedDevice,
    required this.isConnecting,
    required this.onTap,
    required this.onLongPress,
  });

  bool get _isNearby => scannedDevice != null;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(
          Icons.electric_scooter,
          color: _isNearby ? AppTheme.primary : AppTheme.textSecondary,
        ),
        title: Text(
          device.name,
          style: TextStyle(
            color: _isNearby ? Colors.white : AppTheme.textSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Text(
          _isNearby
              ? '${device.mac}  ${scannedDevice!.rssi} dBm'
              : '${device.mac}  Saved',
          style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
        ),
        trailing: _isNearby
            ? Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.success.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'Nearby',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppTheme.success,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              )
            : null,
        onTap: isConnecting ? null : onTap,
        onLongPress: onLongPress,
      ),
    );
  }
}

class _ConnectionProgressDialog extends ConsumerStatefulWidget {
  final VoidCallback onConnected;
  final VoidCallback onCancel;

  const _ConnectionProgressDialog({
    required this.onConnected,
    required this.onCancel,
  });

  @override
  ConsumerState<_ConnectionProgressDialog> createState() =>
      _ConnectionProgressDialogState();
}

class _ConnectionProgressDialogState
    extends ConsumerState<_ConnectionProgressDialog> {
  bool _navigated = false;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(connectionProvider);

    // Auto-navigate on success
    if (state.isConnected && !_navigated) {
      _navigated = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          Navigator.of(context).pop();
          widget.onConnected();
        }
      });
    }

    // Refresh saved devices list after successful connection
    if (state.isConnected) {
      ref.invalidate(savedDevicesProvider);
    }

    final isError = state.phase == ConnectionPhase.error;
    final title = switch (state.phase) {
      ConnectionPhase.connecting => 'Connecting...',
      ConnectionPhase.handshaking => 'Authenticating...',
      ConnectionPhase.connected => 'Connected!',
      ConnectionPhase.error => 'Connection Failed',
      _ => 'Connecting...',
    };

    return AlertDialog(
      backgroundColor: AppTheme.surface,
      title: Text(title, style: const TextStyle(color: Colors.white)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!isError)
            const SizedBox(
              width: 48,
              height: 48,
              child: CircularProgressIndicator(color: AppTheme.primary),
            )
          else
            const Icon(Icons.error_outline, size: 48, color: AppTheme.error),
          const SizedBox(height: 16),
          Text(
            isError ? (state.error ?? 'Unknown error') : (state.message ?? ''),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: isError ? AppTheme.error : AppTheme.textSecondary,
              fontSize: 14,
            ),
          ),
        ],
      ),
      actions: [
        if (isError)
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          )
        else
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              widget.onCancel();
            },
            child: const Text('Cancel'),
          ),
      ],
    );
  }
}

class _PasswordImportDialog extends StatefulWidget {
  final void Function(Uint8List password, Uint8List? commandIdent) onSubmit;

  const _PasswordImportDialog({required this.onSubmit});

  @override
  State<_PasswordImportDialog> createState() => _PasswordImportDialogState();
}

class _PasswordImportDialogState extends State<_PasswordImportDialog> {
  final _passwordController = TextEditingController();
  final _identController = TextEditingController();
  String? _passwordError;
  String? _identError;

  Uint8List? _parseHex(String hex) {
    final clean = hex.replaceAll(RegExp(r'\s+'), '').toLowerCase();
    if (clean.length != 32) return null;
    if (!RegExp(r'^[0-9a-f]{32}$').hasMatch(clean)) return null;
    final bytes = Uint8List(16);
    for (var i = 0; i < 16; i++) {
      bytes[i] = int.parse(clean.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return bytes;
  }

  @override
  void dispose() {
    _passwordController.dispose();
    _identController.dispose();
    super.dispose();
  }

  InputDecoration _decoration(String hint, String? error) => InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(
          color: AppTheme.textSecondary.withValues(alpha: 0.5),
          fontFamily: 'monospace',
          fontSize: 14,
        ),
        errorText: error,
        enabledBorder: const OutlineInputBorder(
          borderSide: BorderSide(color: AppTheme.textSecondary),
        ),
        focusedBorder: const OutlineInputBorder(
          borderSide: BorderSide(color: AppTheme.primary),
        ),
        errorBorder: const OutlineInputBorder(
          borderSide: BorderSide(color: AppTheme.error),
        ),
        focusedErrorBorder: const OutlineInputBorder(
          borderSide: BorderSide(color: AppTheme.error),
        ),
      );

  Future<void> _scanQr() async {
    final result = await Navigator.of(context).push<CredentialPayload>(
      MaterialPageRoute(builder: (_) => const QrScannerScreen()),
    );
    if (result == null || !mounted) return;
    setState(() {
      _passwordController.text = result.password
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join();
      _passwordError = null;
      if (result.commandIdent != null) {
        _identController.text = result.commandIdent!
            .map((b) => b.toRadixString(16).padLeft(2, '0'))
            .join();
        _identError = null;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppTheme.surface,
      title: const Text('Import Credentials',
          style: TextStyle(color: Colors.white)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            OutlinedButton.icon(
              onPressed: _scanQr,
              icon: const Icon(Icons.qr_code_scanner,
                  color: AppTheme.primary),
              label: const Text('Scan setup QR',
                  style: TextStyle(color: AppTheme.primary)),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(44),
                side: const BorderSide(color: AppTheme.primary),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Or paste values from your iOS backup '
              '(Library/Preferences/com.ninebot.segway.plist).',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 16),
            const Text(
              'Password — UserDefaults key {sn}_decrypt (required)',
              style: TextStyle(color: Colors.white, fontSize: 12),
            ),
            const SizedBox(height: 4),
            TextField(
              controller: _passwordController,
              style: const TextStyle(
                color: Colors.white,
                fontFamily: 'monospace',
                fontSize: 14,
              ),
              decoration: _decoration(
                  '00112233445566778899aabbccddeeff', _passwordError),
              maxLength: 32,
              autocorrect: false,
              enableSuggestions: false,
            ),
            const SizedBox(height: 8),
            const Text(
              'Command ident — UserDefaults key {sn}_ident '
              '(required for power on/off & seat open)',
              style: TextStyle(color: Colors.white, fontSize: 12),
            ),
            const SizedBox(height: 4),
            TextField(
              controller: _identController,
              style: const TextStyle(
                color: Colors.white,
                fontFamily: 'monospace',
                fontSize: 14,
              ),
              decoration: _decoration(
                  'ffeeddccbbaa99887766554433221100 (optional)', _identError),
              maxLength: 32,
              autocorrect: false,
              enableSuggestions: false,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () {
            final pwd = _parseHex(_passwordController.text);
            if (pwd == null) {
              setState(
                  () => _passwordError = 'Must be exactly 32 hex characters');
              return;
            }
            Uint8List? ident;
            final identText = _identController.text.trim();
            if (identText.isNotEmpty) {
              ident = _parseHex(identText);
              if (ident == null) {
                setState(
                    () => _identError = 'Must be exactly 32 hex characters');
                return;
              }
            }
            Navigator.of(context).pop();
            widget.onSubmit(pwd, ident);
          },
          child: const Text('Connect',
              style: TextStyle(color: AppTheme.primary)),
        ),
      ],
    );
  }
}

class _DeviceTile extends StatelessWidget {
  final ScannedDevice device;
  final VoidCallback onTap;
  final bool isConnecting;

  const _DeviceTile({
    required this.device,
    required this.onTap,
    required this.isConnecting,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(
          device.isSegway
              ? Icons.electric_scooter
              : Icons.bluetooth,
          color: device.isSegway ? AppTheme.primary : AppTheme.textSecondary,
        ),
        title: Text(
          device.name,
          style: TextStyle(
            color: device.isSegway ? Colors.white : AppTheme.textSecondary,
            fontWeight: device.isSegway ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
        subtitle: Text(
          '${device.id}  ${device.rssi} dBm',
          style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (device.isSystemDevice)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                margin: const EdgeInsets.only(right: 4),
                decoration: BoxDecoration(
                  color: AppTheme.success.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'Connected',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppTheme.success,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            if (device.isSegway)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'Segway',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppTheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        ),
        onTap: isConnecting ? null : onTap,
      ),
    );
  }
}

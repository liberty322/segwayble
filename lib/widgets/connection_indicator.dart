/// Connection status indicator widget.
library;

import 'package:flutter/material.dart';

import '../providers/connection_provider.dart';
import '../theme/app_theme.dart';

class ConnectionIndicator extends StatelessWidget {
  final BleConnectionState connectionState;

  const ConnectionIndicator({super.key, required this.connectionState});

  Color get _dotColor => switch (connectionState.phase) {
        ConnectionPhase.connected => AppTheme.success,
        ConnectionPhase.connecting ||
        ConnectionPhase.handshaking =>
          AppTheme.warning,
        ConnectionPhase.error => AppTheme.error,
        ConnectionPhase.disconnected => AppTheme.textSecondary,
      };

  String get _label => switch (connectionState.phase) {
        ConnectionPhase.connected =>
          connectionState.deviceName ?? connectionState.serialNumber ?? 'Connected',
        ConnectionPhase.connecting => 'Connecting...',
        ConnectionPhase.handshaking =>
          connectionState.message ?? 'Authenticating...',
        ConnectionPhase.error => 'Error',
        ConnectionPhase.disconnected => 'Disconnected',
      };

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: _dotColor,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            _label,
            style: const TextStyle(fontSize: 14, color: AppTheme.textSecondary),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

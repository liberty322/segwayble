/// Settings index — category tiles that drill into focused sub-screens.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/connection_provider.dart';
import '../providers/vehicle_provider.dart';
import '../theme/app_theme.dart';
import 'settings/advanced_screen.dart';
import 'settings/audio_screen.dart';
import 'settings/config_snapshot_screen.dart';
import 'settings/features_screen.dart';
import 'settings/lights_screen.dart';
import 'settings/riding_modes_screen.dart';
import 'settings/speed_safety_screen.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conn = ref.watch(connectionProvider);
    final vehicle = ref.watch(vehicleProvider);

    if (!conn.isConnected) {
      return Scaffold(
        appBar: AppBar(title: const Text('Settings')),
        body: const Center(
          child: Text('Not connected',
              style: TextStyle(color: AppTheme.textSecondary)),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        actions: [
          IconButton(
            tooltip: 'Refresh all',
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.read(vehicleProvider.notifier).refresh(),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (!vehicle.isPoweredOn)
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.warning.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: AppTheme.warning.withValues(alpha: 0.4)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, color: AppTheme.warning, size: 20),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Some settings are read-only while the vehicle is off. '
                      'Power it on for full access.',
                      style: TextStyle(
                          color: AppTheme.textPrimary, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          _Tile(
            icon: Icons.speed,
            title: 'Speed & safety',
            subtitle: 'Speed limit, TCS, electric brake, slope assist',
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const SpeedSafetyScreen())),
          ),
          _Tile(
            icon: Icons.ev_station,
            title: 'Riding modes',
            subtitle: 'ECO / Coast / Furious / M1 / M2 — select + edit profile',
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const RidingModesScreen())),
          ),
          _Tile(
            icon: Icons.tune,
            title: 'Features',
            subtitle: 'Auto-lock, push assist, parking, reverse, …',
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const FeaturesScreen())),
          ),
          _Tile(
            icon: Icons.volume_up_outlined,
            title: 'Audio',
            subtitle: 'Alarm volume, sound preset',
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const AudioScreen())),
          ),
          _Tile(
            icon: Icons.lightbulb_outline,
            title: 'Lights',
            subtitle: 'Headlight, handle RGB, rear lights (coming soon)',
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const LightsScreen())),
          ),
          _Tile(
            icon: Icons.description_outlined,
            title: 'Current configuration',
            subtitle: 'Snapshot all registers, copy or share as text',
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const ConfigSnapshotScreen())),
          ),
          _Tile(
            icon: Icons.developer_board,
            title: 'Advanced',
            subtitle: 'Config mode, raw register, debug logs',
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const AdvancedScreen())),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _Tile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  alignment: Alignment.center,
                  child: Icon(icon, color: AppTheme.primary, size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: const TextStyle(
                              color: AppTheme.textPrimary,
                              fontSize: 15,
                              fontWeight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      Text(subtitle,
                          style: const TextStyle(
                              color: AppTheme.textSecondary, fontSize: 12)),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right,
                    color: AppTheme.textSecondary, size: 22),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

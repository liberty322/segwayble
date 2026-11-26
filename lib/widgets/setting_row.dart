/// Tappable list row for settings screens.
///
/// Layout:
///   [ label                           current-value › ]
///   [ optional subtitle                                ]
///
/// Always displays the current device value; no inline editing widget.
/// Tapping pushes a detail editor page.
library;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class SettingRow extends StatelessWidget {
  final String label;
  final String? subtitle;
  final String? currentValue;
  final IconData? icon;

  /// Set to false for read-only rows. Hides the chevron, ignores taps.
  final bool tappable;
  final VoidCallback? onTap;

  const SettingRow({
    super.key,
    required this.label,
    this.subtitle,
    this.currentValue,
    this.icon,
    this.tappable = true,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final trailing = <Widget>[];
    if (currentValue != null) {
      trailing.add(Text(
        currentValue!,
        style: const TextStyle(
          color: AppTheme.accent,
          fontSize: 15,
          fontWeight: FontWeight.w600,
          fontFeatures: [FontFeature.tabularFigures()],
        ),
      ));
    }
    if (tappable) {
      trailing.add(const SizedBox(width: 6));
      trailing.add(const Icon(
        Icons.chevron_right,
        color: AppTheme.textSecondary,
        size: 22,
      ));
    }

    return Material(
      color: AppTheme.card,
      child: InkWell(
        onTap: tappable ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              if (icon != null) ...[
                Icon(icon, color: AppTheme.primary, size: 22),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 15,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        style: const TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),
              ...trailing,
            ],
          ),
        ),
      ),
    );
  }
}

/// Groups [SettingRow]s with a section header.
class SettingSection extends StatelessWidget {
  final String title;
  final List<Widget> children;
  final String? description;

  const SettingSection({
    super.key,
    required this.title,
    required this.children,
    this.description,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
            child: Text(
              title.toUpperCase(),
              style: const TextStyle(
                color: AppTheme.primary,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: AppTheme.card,
              borderRadius: BorderRadius.circular(12),
            ),
            clipBehavior: Clip.antiAlias,
            margin: const EdgeInsets.symmetric(horizontal: 12),
            child: Column(
              children: _withDividers(children),
            ),
          ),
          if (description != null) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                description!,
                style: const TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  List<Widget> _withDividers(List<Widget> rows) {
    if (rows.length <= 1) return rows;
    final out = <Widget>[];
    for (var i = 0; i < rows.length; i++) {
      out.add(rows[i]);
      if (i < rows.length - 1) {
        out.add(const Divider(
          height: 1,
          thickness: 1,
          color: AppTheme.surface,
        ));
      }
    }
    return out;
  }
}

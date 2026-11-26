/// Full-screen blocking progress overlay used while a screen's initial
/// BLE register reads are in flight. Card + linear bar + Abort button.
library;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class ProgressOverlay extends StatelessWidget {
  final String title;
  final int done;
  final int total;
  final String label;
  final VoidCallback? onAbort;

  const ProgressOverlay({
    super.key,
    required this.done,
    required this.total,
    required this.label,
    this.title = 'Reading registers',
    this.onAbort,
  });

  @override
  Widget build(BuildContext context) {
    final t = total == 0 ? 1 : total;
    final fraction = (done / t).clamp(0.0, 1.0);
    return Positioned.fill(
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Opaque scrim that swallows taps so the underlying screen
          // can't receive input while we're loading.
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {},
            child: Container(color: Colors.black.withValues(alpha: 0.78)),
          ),
          Center(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 32),
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(16),
                border:
                    Border.all(color: AppTheme.primary.withValues(alpha: 0.4)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppTheme.primary,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    label,
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
                      valueColor:
                          const AlwaysStoppedAnimation<Color>(AppTheme.accent),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '$done / $total  '
                    '(${(fraction * 100).toStringAsFixed(0)}%)',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 12,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                  if (onAbort != null) ...[
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: onAbort,
                      icon: const Icon(Icons.cancel_outlined,
                          color: AppTheme.error),
                      label: const Text(
                        'Abort',
                        style: TextStyle(color: AppTheme.error),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: AppTheme.error),
                        minimumSize: const Size.fromHeight(42),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

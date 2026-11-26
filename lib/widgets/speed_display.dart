/// Large speed readout widget.
library;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class SpeedDisplay extends StatelessWidget {
  final double speed;
  final String unit;

  const SpeedDisplay({
    super.key,
    required this.speed,
    this.unit = 'km/h',
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 160,
          child: Text(
            speed.toStringAsFixed(1),
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 56,
              fontWeight: FontWeight.w300,
              color: AppTheme.accent,
              letterSpacing: -2,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ),
        Text(
          unit,
          style: const TextStyle(
            fontSize: 14,
            color: AppTheme.textSecondary,
          ),
        ),
      ],
    );
  }
}

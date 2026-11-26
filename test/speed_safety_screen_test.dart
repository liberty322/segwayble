/// Render-only smoke tests for settings screens.
///
/// These do NOT exercise writes (that would need a BLE mock); they just
/// override [vehicleProvider] with a fixed [VehicleData] snapshot and
/// assert that the screen surfaces the expected current values.
library;

import 'package:app/providers/vehicle_provider.dart';
import 'package:app/screens/settings/speed_safety_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_test/flutter_test.dart';

class _StubVehicleNotifier extends StateNotifier<VehicleData>
    implements VehicleNotifier {
  _StubVehicleNotifier(super.state);

  @override
  Future<void> refreshSettingsRegisters() async {}

  @override
  void resumePolling(Set<PollTier> tiers, {required String by}) {}

  @override
  void pausePolling({required String by}) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

Widget _withVehicle(VehicleData data, Widget child) {
  final stub = StateNotifierProvider<VehicleNotifier, VehicleData>(
    (_) => _StubVehicleNotifier(data),
  );
  return ProviderScope(
    overrides: [
      vehicleProvider.overrideWith((ref) => _StubVehicleNotifier(data)),
      // ignore: unused_local_variable
      stub,
    ],
    child: MaterialApp(home: child),
  );
}

void main() {
  group('SpeedSafetyScreen rendering', () {
    testWidgets('shows speed safety lock + rated/signage max speeds',
        (tester) async {
      await tester.pumpWidget(_withVehicle(
        const VehicleData(
          limitSpeedRaw: 45,
          ratedSpeedRaw: 250,
          sigMaxSpeedRaw: 180,
        ),
        const SpeedSafetyScreen(),
      ));
      await tester.pump();

      expect(find.text('45 km/h'), findsOneWidget); // lock preset label
      expect(find.text('25.0 km/h'), findsOneWidget); // rated
      expect(find.text('18.0 km/h'), findsOneWidget); // sig max
    });

    testWidgets('unmapped lock value falls back to raw km/h', (tester) async {
      await tester.pumpWidget(_withVehicle(
        const VehicleData(limitSpeedRaw: 30),
        const SpeedSafetyScreen(),
      ));
      await tester.pump();

      expect(find.text('30 km/h'), findsOneWidget);
    });

    testWidgets('shows em-dash for missing values', (tester) async {
      await tester.pumpWidget(
          _withVehicle(const VehicleData(), const SpeedSafetyScreen()));
      await tester.pump();
      expect(find.text('—'), findsWidgets);
    });
  });
}

import 'package:app/providers/vehicle_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('VehicleData.copyWith', () {
    test('only the requested field changes', () {
      const a = VehicleData(
        tcs: 1,
        slope: 2,
        eleBrake: 0,
        gearTopSpeed: 25,
      );
      final b = a.copyWith(tcs: 2);
      expect(b.tcs, 2);
      expect(b.slope, a.slope);
      expect(b.eleBrake, a.eleBrake);
      expect(b.gearTopSpeed, a.gearTopSpeed);
    });

    test('preserves all new settings fields when untouched', () {
      const seed = VehicleData(
        autoLock: 60,
        alarmVolume: 5,
        speedIntensity: 7,
        speedSafeLock: 12,
        tcs: 1,
        slope: 1,
        eleBrake: 1,
        activeGearMask: 0x10,
        gearTopSpeed: 25,
        gearAccSpeed: 50,
        gearAccSens: 2,
        gearTcs: 1,
        gearNitro: 1,
        gearEnergy: 80,
      );
      // Touch only battery, not any setting.
      final next = seed.copyWith(battery: 50);
      expect(next.battery, 50);
      expect(next.autoLock, seed.autoLock);
      expect(next.alarmVolume, seed.alarmVolume);
      expect(next.speedIntensity, seed.speedIntensity);
      expect(next.speedSafeLock, seed.speedSafeLock);
      expect(next.tcs, seed.tcs);
      expect(next.slope, seed.slope);
      expect(next.eleBrake, seed.eleBrake);
      expect(next.activeGearMask, seed.activeGearMask);
      expect(next.gearTopSpeed, seed.gearTopSpeed);
      expect(next.gearAccSpeed, seed.gearAccSpeed);
      expect(next.gearAccSens, seed.gearAccSens);
      expect(next.gearTcs, seed.gearTcs);
      expect(next.gearNitro, seed.gearNitro);
      expect(next.gearEnergy, seed.gearEnergy);
    });

    test('null passed to copyWith keeps current field', () {
      const a = VehicleData(tcs: 2);
      final b = a.copyWith();
      expect(b.tcs, 2);
    });

    test('powered-on derivation — bit 3 of mainPower', () {
      expect(const VehicleData(mainPower: 0x00).isPoweredOn, isFalse);
      expect(const VehicleData(mainPower: 0x08).isPoweredOn, isTrue);
      // Mix of other bits + 0x08 → still powered on
      expect(const VehicleData(mainPower: 0x1F).isPoweredOn, isTrue);
    });

    test('runningTimeFormatted', () {
      expect(const VehicleData(runningTime: 59).runningTimeFormatted, '59s');
      expect(
          const VehicleData(runningTime: 125).runningTimeFormatted, '2m 5s');
      expect(const VehicleData(runningTime: 3600).runningTimeFormatted, '1h 0m');
    });
  });
}

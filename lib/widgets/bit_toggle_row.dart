/// Tappable row that flips one bit of a bitmask register with an
/// undo snackbar. Used for Feature flags (FunBool, CtlBool2).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/connection_provider.dart';
import '../theme/app_theme.dart';

class BitToggleRow extends ConsumerStatefulWidget {
  final String label;
  final String? subtitle;
  final IconData? icon;

  /// The register to mutate.
  final int target;
  final int register;

  /// Bit index (0-15).
  final int bit;

  /// Currently-displayed value of the full register (from VehicleData).
  /// The row shows on/off based on bit's state in this value.
  final int? currentRegisterValue;

  /// Called after a successful write so the caller can patch provider
  /// state (avoids waiting for the next poll tick).
  final void Function(int verifiedValue)? onPatch;

  /// When true, UI-level "on" maps to bit = 0 (and vice versa). Used for
  /// settings like TCS and electric brake where the spec says
  /// `"reverse": true` — the register stores "disabled" as a set bit.
  final bool reversed;

  const BitToggleRow({
    super.key,
    required this.label,
    required this.target,
    required this.register,
    required this.bit,
    required this.currentRegisterValue,
    this.subtitle,
    this.icon,
    this.onPatch,
    this.reversed = false,
  });

  @override
  ConsumerState<BitToggleRow> createState() => _BitToggleRowState();
}

class _BitToggleRowState extends ConsumerState<BitToggleRow> {
  bool _pending = false;

  bool get _bitRawSet {
    final v = widget.currentRegisterValue;
    if (v == null) return false;
    return (v & (1 << widget.bit)) != 0;
  }

  /// Displayed switch state — flipped if `reversed`.
  bool get _uiOn => widget.reversed ? !_bitRawSet : _bitRawSet;

  Future<void> _toggle() async {
    if (_pending || widget.currentRegisterValue == null) return;
    setState(() => _pending = true);
    final conn = ref.read(connectionProvider.notifier);
    // New UI state user wants; convert to the raw bit we need to write.
    final newUiOn = !_uiOn;
    final targetBitSet = widget.reversed ? !newUiOn : newUiOn;
    final verified = await conn.writeAndVerifyBit(
      widget.target,
      widget.register,
      widget.bit,
      targetBitSet,
    );
    if (!mounted) return;
    setState(() => _pending = false);
    if (verified == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Write failed.'),
        duration: Duration(seconds: 2),
      ));
      return;
    }
    widget.onPatch?.call(verified);
    final actualBitSet = (verified & (1 << widget.bit)) != 0;
    final actualUiOn = widget.reversed ? !actualBitSet : actualBitSet;
    if (actualUiOn == newUiOn) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('${widget.label} ${actualUiOn ? "enabled" : "disabled"}'),
        duration: const Duration(seconds: 2),
      ));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('${widget.label} not persisted by device'),
        duration: const Duration(seconds: 3),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final canToggle = widget.currentRegisterValue != null && !_pending;
    final isOn = _uiOn;
    return Material(
      color: AppTheme.card,
      child: InkWell(
        onTap: canToggle ? _toggle : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              if (widget.icon != null) ...[
                Icon(widget.icon, color: AppTheme.primary, size: 22),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.label,
                        style: const TextStyle(
                            color: AppTheme.textPrimary, fontSize: 15)),
                    if (widget.subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(widget.subtitle!,
                          style: const TextStyle(
                              color: AppTheme.textSecondary, fontSize: 12)),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),
              if (_pending)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppTheme.primary,
                  ),
                )
              else
                Switch(
                  value: isOn,
                  onChanged: canToggle ? (_) => _toggle() : null,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

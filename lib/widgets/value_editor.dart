/// Detail page for editing a single numeric setting.
///
/// The editor owns two values: the device's `current` (read-only chip on
/// top) and the user's `pending` (chip + slider + ±step buttons). `Save`
/// is only enabled when they differ. On save, the `onSave` callback
/// performs the actual write-and-verify and returns the value the
/// device accepted (may differ from the requested value if the firmware
/// clamped it — that case is surfaced with a snackbar).
library;

import 'package:flutter/material.dart';

import '../core/logger.dart';
import '../theme/app_theme.dart';

typedef VerifiedWriteCallback = Future<int?> Function(int pendingValue);

class ValueEditor extends StatefulWidget {
  final String title;
  final String? description;

  /// Current device value.
  final int current;

  /// Inclusive bounds of the slider + stepper.
  final int min;
  final int max;

  /// Discrete step size. The stepper buttons add/subtract this, and the
  /// slider snaps to multiples of it. Use 1 for arbitrary integers.
  final int step;

  /// Display function — receives a raw register value, returns a
  /// human-readable string (e.g. `(v) => "$v km/h"`). Applied to both
  /// the current and pending chips and the stepper label.
  final String Function(int value) format;

  /// Called when the user taps Save. Return the post-write device
  /// value (may equal `pending` or be clamped to something else). Return
  /// null on failure.
  final VerifiedWriteCallback onSave;

  const ValueEditor({
    super.key,
    required this.title,
    required this.current,
    required this.min,
    required this.max,
    required this.step,
    required this.format,
    required this.onSave,
    this.description,
  });

  @override
  State<ValueEditor> createState() => _ValueEditorState();
}

class _ValueEditorState extends State<ValueEditor> {
  late int _pending;
  int _lastKnownCurrent = 0;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _lastKnownCurrent = _clamp(widget.current);
    _pending = _lastKnownCurrent;
  }

  int _clamp(int v) {
    if (v < widget.min) return widget.min;
    if (v > widget.max) return widget.max;
    return v;
  }

  void _setPending(int v) {
    final clamped = _clamp(v);
    // Snap to step grid so the pending label matches what'll be sent.
    final snapped = widget.min +
        (((clamped - widget.min) / widget.step).round() * widget.step);
    if (snapped == _pending) return;
    setState(() => _pending = snapped);
  }

  Future<bool> _confirmDiscardIfDirty() async {
    if (_pending == _lastKnownCurrent) return true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text('Discard changes?',
            style: TextStyle(color: Colors.white)),
        content: const Text(
          'Your change has not been sent to the vehicle yet.',
          style: TextStyle(color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Keep editing'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Discard',
                style: TextStyle(color: AppTheme.error)),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  Future<void> _save() async {
    if (_saving || _pending == _lastKnownCurrent) return;
    setState(() => _saving = true);
    final requested = _pending;
    talker.info(
        'ValueEditor[${widget.title}] save: '
        'current=${widget.format(_lastKnownCurrent)} → '
        'requested=${widget.format(requested)}');
    final actual = await widget.onSave(requested);
    if (!mounted) return;
    setState(() => _saving = false);
    talker.info('ValueEditor[${widget.title}] save result: '
        '${actual == null ? "FAILED" : widget.format(actual)}');
    if (actual == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Write failed — check the connection and try again.'),
        duration: Duration(seconds: 3),
      ));
      return;
    }
    setState(() {
      _lastKnownCurrent = _clamp(actual);
      _pending = _lastKnownCurrent;
    });
    if (actual != requested) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
            'Device clamped to ${widget.format(actual)} — out of allowed range.'),
        duration: const Duration(seconds: 3),
      ));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Saved: ${widget.format(actual)}'),
        duration: const Duration(seconds: 2),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDirty = _pending != _lastKnownCurrent;
    return PopScope(
      canPop: !isDirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final nav = Navigator.of(context);
        if (await _confirmDiscardIfDirty() && mounted) {
          nav.pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(title: Text(widget.title)),
        body: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.description != null) ...[
                Text(
                  widget.description!,
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 16),
              ],
              _ValueChip(
                label: 'Currently on vehicle',
                value: widget.format(_lastKnownCurrent),
                color: AppTheme.textSecondary,
              ),
              const SizedBox(height: 12),
              _ValueChip(
                label: isDirty ? 'New value (unsaved)' : 'Selected value',
                value: widget.format(_pending),
                color: isDirty ? AppTheme.accent : AppTheme.textSecondary,
              ),
              const SizedBox(height: 24),
              _StepperSlider(
                min: widget.min,
                max: widget.max,
                step: widget.step,
                value: _pending,
                formatSmall: widget.format,
                onChanged: _setPending,
              ),
              const Spacer(),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () async {
                        final nav = Navigator.of(context);
                        if (await _confirmDiscardIfDirty() && mounted) {
                          nav.pop();
                        }
                      },
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: (isDirty && !_saving) ? _save : null,
                      child: _saving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.black,
                              ),
                            )
                          : const Text('Save'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ValueChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _ValueChip({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 26,
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _StepperSlider extends StatelessWidget {
  final int min;
  final int max;
  final int step;
  final int value;
  final String Function(int) formatSmall;
  final ValueChanged<int> onChanged;

  const _StepperSlider({
    required this.min,
    required this.max,
    required this.step,
    required this.value,
    required this.formatSmall,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final divisions =
        ((max - min) / step).round().clamp(1, 1000);
    final stepLabel = step == 1 ? '±1' : '±$step';

    return Column(
      children: [
        Row(
          children: [
            IconButton.outlined(
              onPressed: value > min ? () => onChanged(value - step) : null,
              icon: Icon(Icons.remove, size: 22),
              tooltip: stepLabel,
            ),
            Expanded(
              child: Slider(
                value: value.toDouble().clamp(
                      min.toDouble(),
                      max.toDouble(),
                    ),
                min: min.toDouble(),
                max: max.toDouble(),
                divisions: divisions,
                label: formatSmall(value),
                onChanged: (v) => onChanged(v.round()),
              ),
            ),
            IconButton.outlined(
              onPressed: value < max ? () => onChanged(value + step) : null,
              icon: Icon(Icons.add, size: 22),
              tooltip: stepLabel,
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(formatSmall(min),
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 11,
                  )),
              Text(formatSmall(max),
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 11,
                  )),
            ],
          ),
        ),
      ],
    );
  }
}

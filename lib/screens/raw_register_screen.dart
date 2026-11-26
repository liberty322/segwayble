/// Debug screen: read/write arbitrary BLE registers.
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/connection_provider.dart';
import '../theme/app_theme.dart';

class RawRegisterScreen extends ConsumerStatefulWidget {
  const RawRegisterScreen({super.key});

  @override
  ConsumerState<RawRegisterScreen> createState() => _RawRegisterScreenState();
}

class _RawRegisterScreenState extends ConsumerState<RawRegisterScreen> {
  final _boardController = TextEditingController(text: '01');
  final _registerController = TextEditingController(text: 'B5');
  final _lengthController = TextEditingController(text: '2');
  final _writeDataController = TextEditingController();
  final _history = <_RegisterEntry>[];

  static const _boards = {
    '01': 'DIS',
    '04': 'BLE',
    '09': 'VCU',
    '20': 'MCU',
    '22': 'BMS1',
    '23': 'BMS2',
    '28': 'HEP',
  };

  @override
  Widget build(BuildContext context) {
    final conn = ref.watch(connectionProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Raw Registers')),
      body: !conn.isConnected
          ? const Center(child: Text('Not connected'))
          : Column(
              children: [
                // Input section
                Container(
                  padding: const EdgeInsets.all(16),
                  color: AppTheme.surface,
                  child: Column(
                    children: [
                      // Board selector
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue: _boardController.text,
                              decoration: const InputDecoration(
                                  labelText: 'Board'),
                              items: _boards.entries
                                  .map((e) => DropdownMenuItem(
                                        value: e.key,
                                        child: Text(
                                            '0x${e.key} (${e.value})'),
                                      ))
                                  .toList(),
                              onChanged: (v) {
                                if (v != null) _boardController.text = v;
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          SizedBox(
                            width: 100,
                            child: TextField(
                              controller: _registerController,
                              decoration: const InputDecoration(
                                labelText: 'Register',
                                prefixText: '0x',
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          SizedBox(
                            width: 60,
                            child: TextField(
                              controller: _lengthController,
                              decoration:
                                  const InputDecoration(labelText: 'Len'),
                              keyboardType: TextInputType.number,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: _read,
                              icon: const Icon(Icons.download, size: 18),
                              label: const Text('Read'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: _writeDataController,
                              decoration: const InputDecoration(
                                labelText: 'Write data (hex)',
                                hintText: 'e.g. 1400',
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton.icon(
                            onPressed: _write,
                            icon: const Icon(Icons.upload, size: 18),
                            label: const Text('Write'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.warning,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // History
                Expanded(
                  child: _history.isEmpty
                      ? const Center(
                          child: Text(
                            'No register reads yet',
                            style:
                                TextStyle(color: AppTheme.textSecondary),
                          ),
                        )
                      : ListView.builder(
                          reverse: true,
                          padding: const EdgeInsets.all(8),
                          itemCount: _history.length,
                          itemBuilder: (_, i) {
                            final entry = _history[_history.length - 1 - i];
                            return _HistoryTile(entry: entry);
                          },
                        ),
                ),
              ],
            ),
    );
  }

  Future<void> _read() async {
    final board = int.parse(_boardController.text, radix: 16);
    final register = int.parse(_registerController.text, radix: 16);
    final length = int.parse(_lengthController.text);

    try {
      final conn = ref.read(connectionProvider.notifier);
      final resp = await conn.readRegister(board, register, readLen: length);

      setState(() {
        _history.add(_RegisterEntry(
          board: board,
          register: register,
          isWrite: false,
          data: resp?.data,
          cmd: resp?.cmd,
          index: resp?.index,
          timestamp: DateTime.now(),
        ));
      });
    } catch (e) {
      setState(() {
        _history.add(_RegisterEntry(
          board: board,
          register: register,
          isWrite: false,
          error: e.toString(),
          timestamp: DateTime.now(),
        ));
      });
    }
  }

  Future<void> _write() async {
    final board = int.parse(_boardController.text, radix: 16);
    final register = int.parse(_registerController.text, radix: 16);
    final hex = _writeDataController.text.replaceAll(' ', '');
    if (hex.isEmpty) return;

    final data = Uint8List(hex.length ~/ 2);
    for (var i = 0; i < data.length; i++) {
      data[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }

    try {
      await ref
          .read(connectionProvider.notifier)
          .writeRegister(board, register, data);

      setState(() {
        _history.add(_RegisterEntry(
          board: board,
          register: register,
          isWrite: true,
          data: data,
          timestamp: DateTime.now(),
        ));
      });
    } catch (e) {
      setState(() {
        _history.add(_RegisterEntry(
          board: board,
          register: register,
          isWrite: true,
          error: e.toString(),
          timestamp: DateTime.now(),
        ));
      });
    }
  }

  @override
  void dispose() {
    _boardController.dispose();
    _registerController.dispose();
    _lengthController.dispose();
    _writeDataController.dispose();
    super.dispose();
  }
}

class _RegisterEntry {
  final int board;
  final int register;
  final bool isWrite;
  final Uint8List? data;
  final int? cmd;
  final int? index;
  final String? error;
  final DateTime timestamp;

  _RegisterEntry({
    required this.board,
    required this.register,
    required this.isWrite,
    this.data,
    this.cmd,
    this.index,
    this.error,
    required this.timestamp,
  });

  String get dataHex =>
      data?.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ') ?? '';

  String? get dataDecimal {
    if (data == null) return null;
    if (data!.length == 2) {
      return '${data![0] | (data![1] << 8)}';
    }
    if (data!.length == 4) {
      return '${data![0] | (data![1] << 8) | (data![2] << 16) | (data![3] << 24)}';
    }
    return null;
  }
}

class _HistoryTile extends StatelessWidget {
  final _RegisterEntry entry;

  const _HistoryTile({required this.entry});

  @override
  Widget build(BuildContext context) {
    final label =
        '[0x${entry.board.toRadixString(16).padLeft(2, '0')}:'
        '0x${entry.register.toRadixString(16).padLeft(2, '0')}]';
    final time =
        '${entry.timestamp.hour.toString().padLeft(2, '0')}:'
        '${entry.timestamp.minute.toString().padLeft(2, '0')}:'
        '${entry.timestamp.second.toString().padLeft(2, '0')}';

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 2),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  entry.isWrite ? Icons.upload : Icons.download,
                  size: 14,
                  color: entry.isWrite ? AppTheme.warning : AppTheme.primary,
                ),
                const SizedBox(width: 4),
                Text(
                  '$label ${entry.isWrite ? "WRITE" : "READ"}',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'monospace',
                  ),
                ),
                const Spacer(),
                Text(
                  time,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
            if (entry.error != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  entry.error!,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppTheme.error,
                  ),
                ),
              )
            else if (entry.data != null) ...[
              const SizedBox(height: 4),
              Text(
                entry.dataHex,
                style: const TextStyle(
                  fontSize: 13,
                  fontFamily: 'monospace',
                  color: AppTheme.accent,
                ),
              ),
              if (entry.dataDecimal != null)
                Text(
                  '= ${entry.dataDecimal}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppTheme.textSecondary,
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

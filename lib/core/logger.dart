import 'package:talker/talker.dart';

/// Minimum log level for console output.
/// TalkerScreen (in-app viewer) always shows full history regardless.
LogLevel _consoleLevel = LogLevel.info;

/// Whether verbose/debug logs are printed to console.
bool get isVerboseLogging => _consoleLevel == LogLevel.verbose;

/// Toggle verbose console logging at runtime.
void setVerboseLogging(bool verbose) {
  _consoleLevel = verbose ? LogLevel.verbose : LogLevel.info;
}

final talker = Talker(
  settings: TalkerSettings(
    maxHistoryItems: 1000,
    useConsoleLogs: false, // We control console output via observer
  ),
  observer: _LevelFilterObserver(),
);

class _LevelFilterObserver extends TalkerObserver {
  @override
  void onLog(TalkerData log) {
    final level = log.logLevel;
    if (level == null || level.index >= _consoleLevel.index) {
      // ignore: avoid_print
      print(log.generateTextMessage());
    }
  }

  @override
  void onError(TalkerError err) {
    // ignore: avoid_print
    print(err.generateTextMessage());
  }

  @override
  void onException(TalkerException exception) {
    // ignore: avoid_print
    print(exception.generateTextMessage());
  }
}

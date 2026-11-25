/// Android: runs a foreground service (with a "MarkETHER bot running"
/// notification) so Android keeps the app process alive in the background.
/// The bot itself runs in the main isolate; the service's task handler only
/// keeps the process awake. The service is declared with stopWithTask, so
/// swiping the app away from recent apps ends the session.
library;

import 'dart:io';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';

@pragma('vm:entry-point')
void markEtherStartCallback() {
  FlutterForegroundTask.setTaskHandler(_KeepAliveHandler());
}

class _KeepAliveHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}
}

class BackgroundKeeper {
  static bool _initialized = false;

  static void initPort() {
    if (!Platform.isAndroid) return;
    try {
      FlutterForegroundTask.initCommunicationPort();
    } catch (_) {}
  }

  static void _init() {
    if (_initialized) return;
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'markether_bot',
        channelName: 'MarkETHER bot',
        channelDescription: 'Shown while the MarkETHER trading bot is running.',
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(60000),
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
    _initialized = true;
  }

  static Future<void> start(String text) async {
    if (!Platform.isAndroid) return;
    try {
      final perm = await FlutterForegroundTask.checkNotificationPermission();
      if (perm != NotificationPermission.granted) {
        await FlutterForegroundTask.requestNotificationPermission();
      }
      _init();
      if (await FlutterForegroundTask.isRunningService) {
        await FlutterForegroundTask.updateService(
            notificationTitle: 'MarkETHER bot running', notificationText: text);
      } else {
        await FlutterForegroundTask.startService(
          serviceId: 717,
          notificationTitle: 'MarkETHER bot running',
          notificationText: text,
          callback: markEtherStartCallback,
        );
      }
    } catch (_) {
      // If the service can't start, the bot still runs while the app is open.
    }
  }

  static Future<void> update(String text) async {
    if (!Platform.isAndroid) return;
    try {
      if (await FlutterForegroundTask.isRunningService) {
        await FlutterForegroundTask.updateService(
            notificationTitle: 'MarkETHER bot running', notificationText: text);
      }
    } catch (_) {}
  }

  static Future<void> stop() async {
    if (!Platform.isAndroid) return;
    try {
      await FlutterForegroundTask.stopService();
    } catch (_) {}
  }
}

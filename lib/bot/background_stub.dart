/// Web build: browsers have no background service; the bot runs while the
/// tab is open.
class BackgroundKeeper {
  static void initPort() {}
  static Future<void> start(String text) async {}
  static Future<void> update(String text) async {}
  static Future<void> stop() async {}
}

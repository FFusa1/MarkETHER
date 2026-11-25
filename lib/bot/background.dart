/// Keeps the bot running while the app is in the background.
/// Android: a foreground service with a notification. Web: no-op.
library;

export 'background_stub.dart' if (dart.library.io) 'background_android.dart';

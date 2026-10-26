import 'dart:async';

/// Helpers for starting independent reads together instead of one after another.
class Concurrent {
  Concurrent._();

  /// Returns [future] unchanged, after making sure an error from it is not
  /// *also* reported as an uncaught error while nothing is awaiting it yet.
  ///
  /// Starting a read before the code that consumes it - so it overlaps with the
  /// other reads instead of queuing behind them - opens a short window in which
  /// the future has no listener. If it fails inside that window Dart reports the
  /// failure to the zone as uncaught, even though the code awaits it a moment
  /// later. The error is still delivered, unchanged, to whoever awaits the
  /// returned future: exactly where the original sequential code threw it.
  static Future<T> start<T>(Future<T> future) {
    future.then<void>((T _) {}, onError: (Object _, StackTrace _) {});
    return future;
  }
}

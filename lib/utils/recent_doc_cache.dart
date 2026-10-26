import 'dart:async';

/// A very short-lived in-memory memo of single Firestore documents, for the
/// reads the vendor app repeats back to back.
///
/// ## Why this exists
///
/// The vendor app is round-trip bound, not data bound. Opening it reads the
/// same small documents several times within a second or two:
///
/// * `sections/{id}` - the splash screen reads the vendor's section, then the
///   dashboard reads it again, then reads the vendor's section again;
/// * `vendors/{id}` - the dashboard reads the store, and the Home tab it opens
///   straight away reads the same store again; Products and Dine-in do the same
///   on every tab visit.
///
/// Each of those is a network round trip the screen waits on, for a document
/// that was fetched a moment ago.
///
/// ## What it deliberately is not
///
/// * **Not a persistence layer.** Nothing is written to disk.
/// * **Not a shared object.** The raw document data is stored, and every caller
///   gets its own deep copy to build its model from - exactly what a fresh
///   `get()` hands back. A screen that edits its `VendorModel` (the models keep
///   the document's lists by reference) can never change what the next screen
///   sees.
/// * **Not long-lived.** Callers choose the lifetime per collection and keep it
///   short; see [FireStoreUtils.getVendorById] and
///   [FireStoreUtils.getSectionById].
///
/// ## Two behaviours, both load-bearing
///
/// 1. **Memoisation** - a repeat read inside the lifetime is served from memory.
/// 2. **In-flight de-duplication** - callers asking for the same document while
///    it is being fetched share that one request.
///
/// A missing document (`null`) and a failed read are never stored, so they are
/// retried by the very next caller, as before.
///
/// Every write the app makes to a memoised document calls [invalidate]; an
/// invalidation that lands while a read of that document is still in flight
/// also stops that read's (pre-write) result from being stored.
class RecentDocCache {
  RecentDocCache._();

  static final Map<String, _Entry> _entries = <String, _Entry>{};
  static final Map<String, Future<Map<String, dynamic>?>> _inFlight = <String, Future<Map<String, dynamic>?>>{};
  static final Set<String> _staleInFlight = <String>{};

  /// Serves the document at [path] from memory when a copy younger than [ttl]
  /// exists, otherwise runs [load] (sharing a load already in flight).
  static Future<Map<String, dynamic>?> read(String path, Future<Map<String, dynamic>?> Function() load, {required Duration ttl}) async {
    final _Entry? entry = _entries[path];
    if (entry != null) {
      if (DateTime.now().isBefore(entry.expiresAt)) return deepCopyMap(entry.data);
      _entries.remove(path);
    }

    final Future<Map<String, dynamic>?>? pending = _inFlight[path];
    if (pending != null) {
      final Map<String, dynamic>? shared = await pending;
      return shared == null ? null : deepCopyMap(shared);
    }

    final Future<Map<String, dynamic>?> future = load();
    _inFlight[path] = future;
    try {
      final Map<String, dynamic>? data = await future;
      if (data != null && !_staleInFlight.contains(path)) {
        _entries[path] = _Entry(deepCopyMap(data), DateTime.now().add(ttl));
      }
      return data == null ? null : deepCopyMap(data);
    } finally {
      if (identical(_inFlight[path], future)) _inFlight.remove(path);
      _staleInFlight.remove(path);
    }
  }

  /// Drops [path], so the next read goes to Firestore. Call after every write.
  static void invalidate(String? path) {
    if (path == null) return;
    _entries.remove(path);
    if (_inFlight.containsKey(path)) _staleInFlight.add(path);
  }

  /// Drops everything.
  static void clear() {
    _entries.clear();
    _staleInFlight.addAll(_inFlight.keys);
  }

  /// Test seam: whether [path] would be served from memory right now.
  static bool isFresh(String path) {
    final _Entry? entry = _entries[path];
    return entry != null && DateTime.now().isBefore(entry.expiresAt);
  }

  /// A copy of [source] that shares no map or list with it.
  ///
  /// Leaf values (strings, numbers, `Timestamp`, `GeoPoint`, `DocumentReference`)
  /// are immutable and are shared. Map and list types are kept as they came from
  /// Firestore, so a model's `is String` / `?? []` checks behave identically.
  static Map<String, dynamic> deepCopyMap(Map<String, dynamic> source) {
    return <String, dynamic>{for (final MapEntry<String, dynamic> e in source.entries) e.key: _copyValue(e.value)};
  }

  static dynamic _copyValue(dynamic value) {
    if (value is Map<String, dynamic>) return deepCopyMap(value);
    if (value is Map) return <dynamic, dynamic>{for (final MapEntry<dynamic, dynamic> e in value.entries) e.key: _copyValue(e.value)};
    if (value is List) return <dynamic>[for (final dynamic item in value) _copyValue(item)];
    return value;
  }
}

class _Entry {
  _Entry(this.data, this.expiresAt);

  final Map<String, dynamic> data;
  final DateTime expiresAt;
}

import 'dart:async';
import 'dart:collection';

/// Shares duplicate requests and limits concurrent controller health checks.
class DelayTestQueue {
  DelayTestQueue({this.concurrency = 4}) : assert(concurrency > 0);

  final int concurrency;
  final _pending = Queue<({String key, Future<void> Function() run})>();
  final _requests = <String, Completer<void>>{};
  var _active = 0;
  var _disposed = false;

  Future<void> schedule(String key, Future<void> Function() run) {
    if (_disposed) return Future<void>.value();
    final existing = _requests[key];
    if (existing != null) return existing.future;
    final result = Completer<void>();
    _requests[key] = result;
    _pending.add((key: key, run: run));
    _drain();
    return result.future;
  }

  void _drain() {
    while (!_disposed && _active < concurrency && _pending.isNotEmpty) {
      final task = _pending.removeFirst();
      final result = _requests[task.key]!;
      _active++;
      unawaited(() async {
        try {
          await task.run();
          result.complete();
        } catch (error, stack) {
          result.completeError(error, stack);
        } finally {
          _requests.remove(task.key);
          _active--;
          _drain();
        }
      }());
    }
  }

  void dispose() {
    _disposed = true;
    while (_pending.isNotEmpty) {
      final task = _pending.removeFirst();
      _requests.remove(task.key)!.complete();
    }
  }
}

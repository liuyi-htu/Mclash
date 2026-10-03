import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mclash/shared/delay_test_queue.dart';

void main() {
  test('limits concurrency, shares duplicates and drains after completion',
      () async {
    final queue = DelayTestQueue(concurrency: 2);
    final gates = List.generate(3, (_) => Completer<void>());
    final started = <int>[];
    Future<void> run(int i) => queue.schedule('$i', () {
          started.add(i);
          return gates[i].future;
        });
    final first = run(0);
    final duplicate = run(0);
    final second = run(1);
    final third = run(2);
    expect(identical(first, duplicate), isTrue);
    expect(started, [0, 1]);
    gates[0].complete();
    await first;
    expect(started, [0, 1, 2]);
    gates[1].complete();
    gates[2].complete();
    await Future.wait([second, third]);
    await queue.schedule('0', () async => started.add(0));
    expect(started, [0, 1, 2, 0]);
    queue.dispose();
  });

  test('a failed request releases its slot and can be retried', () async {
    final queue = DelayTestQueue(concurrency: 1);
    final gate = Completer<void>();
    final failed = queue.schedule('A', () => gate.future);
    final expectation = expectLater(failed, throwsStateError);
    var nextRan = false;
    final next = queue.schedule('B', () async => nextRan = true);
    gate.completeError(StateError('failed'));
    await expectation;
    await next;
    expect(nextRan, isTrue);
    await queue.schedule('A', () async {});
    queue.dispose();
  });

  test('dispose skips pending requests and prevents new requests', () async {
    final queue = DelayTestQueue(concurrency: 1);
    final gate = Completer<void>();
    final active = queue.schedule('A', () => gate.future);
    var calls = 0;
    final pending = queue.schedule('B', () async => calls++);
    queue.dispose();
    await pending;
    await queue.schedule('C', () async => calls++);
    expect(calls, 0);
    gate.complete();
    await active;
  });
}

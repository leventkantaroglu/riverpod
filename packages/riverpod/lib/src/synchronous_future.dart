// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';

import 'package:meta/meta.dart';

/// A [Future] whose [then] implementation calls the callback immediately.
///
/// This is similar to [Future.value], except that the value is available in
/// the same event-loop iteration.
///
/// ⚠ This class is useful in cases where you want to expose a single API, where
/// you normally want to have everything execute synchronously, but where on
/// rare occasions you want the ability to switch to an asynchronous model. **In
/// general use of this class should be avoided as it is very difficult to debug
/// such bimodal behavior.**
@internal
@immutable
class SynchronousFuture<T> implements Future<T> {
  /// Creates a synchronous future.
  ///
  /// See also:
  ///
  ///  * [Future.value] for information about creating a regular
  ///    [Future] that completes with a value.
  // ignore: prefer_const_constructors_in_immutables
  SynchronousFuture(this.value);

  /// The value that is synchronously emitted by this [Future].
  final T value;

  @override
  Stream<T> asStream() {
    final controller = StreamController<T>();
    controller.add(value);
    controller.close();
    return controller.stream;
  }

  @override
  Future<T> catchError(Function onError, {bool Function(Object error)? test}) {
    return this;
  }

  @override
  Future<R> then<R>(
    FutureOr<R> Function(T value) onValue, {
    Function? onError,
  }) {
    final dynamic result = onValue(value);
    if (result is Future<R>) {
      return result;
    }
    return SynchronousFuture<R>(result as R);
  }

  @override
  Future<T> timeout(Duration timeLimit, {FutureOr<T> Function()? onTimeout}) {
    return Future<T>.value(value).timeout(timeLimit, onTimeout: onTimeout);
  }

  @override
  Future<T> whenComplete(FutureOr<dynamic> Function() action) {
    try {
      final result = action();
      if (result is Future) {
        return result.then<T>((dynamic value) => this.value);
      }
      return this;
    } catch (e, stack) {
      return Future<T>.error(e, stack);
    }
  }

  @override
  bool operator ==(Object other) =>
      other is SynchronousFuture<int> && other.value == value;

  @override
  int get hashCode => Object.hash(runtimeType, value);

  @override
  String toString() {
    return 'SynchronousFuture<$T>($value)';
  }
}

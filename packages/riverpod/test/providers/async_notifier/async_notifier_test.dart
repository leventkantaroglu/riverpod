// ignore_for_file: avoid_types_on_closure_parameters

import 'dart:async';

import 'package:meta/meta.dart';
import 'package:mockito/mockito.dart';
import 'package:riverpod/riverpod.dart' hide ErrorListener;
import 'package:riverpod/src/synchronous_future.dart';
import 'package:test/test.dart';

import '../../utils.dart';
import 'factory.dart';

void main() {
  for (final factory in matrix()) {
    group(factory.label, () {
      group('supports refresh transition', () {
        test(
            'sets isRefreshing to true if triggered by a ref.invalidate/ref.refresh',
            () async {
          final container = createContainer();
          var count = 0;
          final provider = factory.simpleTestProvider(
            (ref) => Future.value(count++),
          );

          container.listen(provider, (previous, next) {});

          await expectLater(container.read(provider.future), completion(0));
          expect(container.read(provider), const AsyncData(0));

          expect(
            container.refresh(provider),
            const AsyncLoading<int>().copyWithPrevious(const AsyncData(0)),
          );

          await expectLater(container.read(provider.future), completion(1));
          expect(container.read(provider), const AsyncData(1));

          container.invalidate(provider);

          expect(
            container.read(provider),
            const AsyncLoading<int>().copyWithPrevious(const AsyncData(1)),
          );
          await expectLater(container.read(provider.future), completion(2));
          expect(container.read(provider), const AsyncData(2));
        });

        test('does not set isRefreshing if triggered by a dependency change',
            () async {
          final container = createContainer();
          final dep = StateProvider((ref) => 0);
          final provider = factory.simpleTestProvider(
            (ref) => Future.value(ref.watch(dep)),
          );

          container.listen(provider, (previous, next) {});

          await expectLater(container.read(provider.future), completion(0));
          expect(container.read(provider), const AsyncData(0));

          container.read(dep.notifier).state++;
          expect(container.read(provider), const AsyncLoading<int>());

          await expectLater(container.read(provider.future), completion(1));
          expect(container.read(provider), const AsyncData(1));
        });

        test(
            'does not set isRefreshing if both triggered by a dependency change and ref.refresh',
            () async {
          final container = createContainer();
          final dep = StateProvider((ref) => 0);
          final provider = factory.simpleTestProvider(
            (ref) => Future.value(ref.watch(dep)),
          );

          container.listen(provider, (previous, next) {});

          await expectLater(container.read(provider.future), completion(0));
          expect(container.read(provider), const AsyncData(0));

          container.read(dep.notifier).state++;
          expect(container.refresh(provider), const AsyncLoading<int>());

          await expectLater(container.read(provider.future), completion(1));
          expect(container.read(provider), const AsyncData(1));
        });
      });

      test('does not notify listeners when refreshed during loading', () async {
        final provider = factory.simpleTestProvider((ref) => Future.value(0));
        final container = createContainer();
        final listener = Listener<AsyncValue<int>>();

        container.listen(provider, listener, fireImmediately: true);

        verifyOnly(listener, listener(null, const AsyncLoading()));

        container.refresh(provider);

        await container.read(provider.future);

        verifyOnly(
          listener,
          listener(const AsyncLoading(), const AsyncData(0)),
        );
      });

      test('supports listenSelf', () {
        final listener = Listener<AsyncValue<int>>();
        final onError = ErrorListener();
        final provider = factory.simpleTestProvider<int>((ref) {
          ref.listenSelf(listener, onError: onError);
          Error.throwWithStackTrace(42, StackTrace.empty);
        });
        final container = createContainer();

        container.listen(provider, (previous, next) {});

        verifyOnly(
          listener,
          listener(null, const AsyncError<int>(42, StackTrace.empty)),
        );
        verifyZeroInteractions(onError);

        container.read(provider.notifier).state = const AsyncData(42);

        verifyNoMoreInteractions(onError);
        verifyOnly(
          listener,
          listener(
            const AsyncError<int>(42, StackTrace.empty),
            const AsyncData<int>(42),
          ),
        );
      });

      test(
          'converts AsyncNotifier.build into an AsyncData if the future completes',
          () async {
        final provider = factory.simpleTestProvider((ref) => Future.value(0));
        final container = createContainer();
        final listener = Listener<AsyncValue<int>>();

        container.listen(provider, listener, fireImmediately: true);

        verifyOnly(listener, listener(null, const AsyncLoading()));
        expect(
          container.read(provider.notifier).state,
          const AsyncLoading<int>(),
        );

        expect(await container.read(provider.future), 0);

        verifyOnly(
          listener,
          listener(const AsyncLoading(), const AsyncData(0)),
        );
        expect(
          container.read(provider.notifier).state,
          const AsyncData<int>(0),
        );
      });

      test(
          'converts AsyncNotifier.build into an AsyncError if the future fails',
          () async {
        final provider = factory.simpleTestProvider<int>(
          (ref) => Future.error(0, StackTrace.empty),
        );
        final container = createContainer();
        final listener = Listener<AsyncValue<int>>();

        container.listen(provider, listener, fireImmediately: true);

        verifyOnly(listener, listener(null, const AsyncLoading()));
        expect(
          container.read(provider.notifier).state,
          const AsyncLoading<int>(),
        );

        await expectLater(container.read(provider.future), throwsA(0));

        verifyOnly(
          listener,
          listener(const AsyncLoading(), const AsyncError(0, StackTrace.empty)),
        );
        expect(
          container.read(provider.notifier).state,
          const AsyncError<int>(0, StackTrace.empty),
        );
      });

      test('supports cases where the AsyncNotifier constructor throws',
          () async {
        final provider = factory.testProvider<int>(
          () => Error.throwWithStackTrace(0, StackTrace.empty),
        );
        final container = createContainer();
        final listener = Listener<AsyncValue<int>>();

        container.listen(provider, listener, fireImmediately: true);

        verifyOnly(
          listener,
          listener(null, const AsyncError(0, StackTrace.empty)),
        );
        expect(
          () => container.read(provider.notifier),
          throwsA(0),
        );

        await expectLater(container.read(provider.future), throwsA(0));
      });

      test(
          'synchronously emits AsyncData if AsyncNotifier.build emits synchronously',
          () async {
        final provider = factory.simpleTestProvider<int>((ref) => 0);
        final container = createContainer();
        final listener = Listener<AsyncValue<int>>();

        container.listen(provider, listener, fireImmediately: true);

        verifyOnly(listener, listener(null, const AsyncData(0)));
        expect(container.read(provider.notifier).state, const AsyncData(0));
        expect(container.read(provider.future), SynchronousFuture<int>(0));
      });

      test(
          'synchronously emits AsyncError if AsyncNotifier.build throws synchronously',
          () async {
        final provider = factory.simpleTestProvider<int>(
          (ref) => Error.throwWithStackTrace(42, StackTrace.empty),
        );
        final container = createContainer();
        final listener = Listener<AsyncValue<int>>();

        container.listen(provider, listener, fireImmediately: true);

        verifyOnly(
          listener,
          listener(null, const AsyncError(42, StackTrace.empty)),
        );
        expect(
          container.read(provider.notifier).state,
          const AsyncError<int>(42, StackTrace.empty),
        );
        await expectLater(container.read(provider.future), throwsA(42));
      });

      test(
          'stops listening to the previous future data when the provider rebuilds',
          () async {
        final container = createContainer();
        final dep = StateProvider((ref) => 0);
        final completers = {
          0: Completer<int>.sync(),
          1: Completer<int>.sync(),
        };
        final provider = factory.simpleTestProvider<int>(
          (ref) => completers[ref.watch(dep)]!.future,
        );
        final listener = Listener<AsyncValue<int>>();

        container.listen(provider, listener);

        expect(
          container.read(provider.future),
          completion(21),
          reason: 'The provider rebuilt while the future was still pending, '
              'so .future should resolve with the next value',
        );
        verifyZeroInteractions(listener);
        expect(container.read(provider), const AsyncLoading<int>());

        container.read(dep.notifier).state++;
        completers[0]!.complete(42);

        verifyZeroInteractions(listener);

        expect(container.read(provider.future), completion(21));
        expect(container.read(provider), const AsyncLoading<int>());

        completers[1]!.complete(21);

        expect(await container.read(provider.future), 21);
        expect(container.read(provider), const AsyncData<int>(21));
      });

      test(
          'stops listening to the previous future error when the provider rebuilds',
          () async {
        final container = createContainer();
        final dep = StateProvider((ref) => 0);
        final completers = {
          0: Completer<int>.sync(),
          1: Completer<int>.sync(),
        };
        final provider = factory.simpleTestProvider<int>(
          (ref) => completers[ref.watch(dep)]!.future,
        );
        final listener = Listener<AsyncValue<int>>();

        container.listen(provider, listener);

        expect(
          container.read(provider.future),
          throwsA(21),
          reason: 'The provider rebuilt while the future was still pending, '
              'so .future should resolve with the next value',
        );
        verifyZeroInteractions(listener);
        expect(container.read(provider), const AsyncLoading<int>());

        container.read(dep.notifier).state++;
        completers[0]!.completeError(42, StackTrace.empty);

        verifyZeroInteractions(listener);

        expect(container.read(provider.future), throwsA(21));
        expect(container.read(provider), const AsyncLoading<int>());

        completers[1]!.completeError(21, StackTrace.empty);

        await expectLater(container.read(provider.future), throwsA(21));
        expect(
          container.read(provider),
          const AsyncError<int>(21, StackTrace.empty),
        );
      });

      group('AsyncNotifier.state', () {
        test(
            'when manually modifying the state, the new exposed value is identical to what is passed to the settter',
            () async {
          final provider = factory.simpleTestProvider<int>((ref) => 0);
          final container = createContainer();

          final sub = container.listen(provider.notifier, (previous, next) {});

          // ignore: prefer_const_constructors, not using `const` as we voluntarility break identity to test `identical`
          final newState = AsyncData(84);
          // ignore: prefer_const_constructors, not using `const` as we voluntarility break identity to test `identical`
          final newLoading = AsyncLoading<int>();
          // ignore: prefer_const_constructors, not using `const` as we voluntarility break identity to test `identical`
          final newError = AsyncError<int>(84, StackTrace.empty);

          sub.read().state = newState;

          expect(sub.read().state, same(newState));

          sub.read().state = newLoading;

          expect(sub.read().state, same(newLoading));

          sub.read().state = newError;

          expect(sub.read().state, same(newError));
        });

        test(
            'when read on outdated provider, refreshes the provider and return the up-to-date state',
            () async {
          final listener = OnBuildMock();
          final dep = StateProvider((ref) => 0);
          final provider = factory.simpleTestProvider<int>(
            (ref) {
              listener();
              return Future.value(ref.watch(dep));
            },
          );
          final container = createContainer();

          container.listen(provider, (previous, next) {});
          final notifier = container.read(provider.notifier);

          expect(notifier.state, const AsyncLoading<int>());
          expect(await container.read(provider.future), 0);
          expect(notifier.state, const AsyncData(0));
          verify(listener()).called(1);

          container.read(dep.notifier).state++;

          expect(notifier.state, const AsyncLoading<int>());
          expect(await container.read(provider.future), 1);
          expect(notifier.state, const AsyncData(1));
          verify(listener()).called(1);
        });

        test('can be read inside build', () {
          final dep = StateProvider((ref) => 0);
          late AsyncValue<int> state;
          final provider = factory.testProvider<int>(
            () {
              late AsyncTestNotifierBase<int> notifier;
              return notifier = factory.notifier<int>(
                (ref) {
                  state = notifier.state;
                  return Future.value(ref.watch(dep));
                },
              );
            },
          );
          final container = createContainer();

          container.listen(provider, (previous, next) {});

          expect(state, const AsyncLoading<int>());

          container.read(provider.notifier).state = const AsyncData(42);
          container.refresh(provider);

          expect(
            state,
            const AsyncLoading<int>().copyWithPrevious(const AsyncData(42)),
          );
        });

        test('notifies listeners when the setter is called', () {
          final provider = factory.simpleTestProvider((ref) => 0);
          final container = createContainer();
          final listener = Listener<AsyncValue<int>>();

          container.listen(provider, listener);

          verifyZeroInteractions(listener);

          container.read(provider.notifier).state = const AsyncData(42);

          verifyOnly(
            listener,
            listener(const AsyncData(0), const AsyncData(42)),
          );
        });
      });

      group('AsyncNotifier.future', () {
        test(
            'when disposed during loading, resolves with the content of AsyncNotifier.build',
            () async {
          final container = createContainer();
          final completer = Completer<int>.sync();
          final provider = factory.simpleTestProvider<int>(
            (ref) => completer.future,
          );

          final future = container.read(provider.future);
          container.dispose();

          completer.complete(42);

          await expectLater(future, completion(42));
        });

        test(
            'when disposed during loading, resolves with the error of AsyncNotifier.build',
            () async {
          final container = createContainer();
          final completer = Completer<int>.sync();
          final provider = factory.simpleTestProvider<int>(
            (ref) => completer.future,
          );

          final future = container.read(provider.future);
          container.dispose();

          completer.completeError(42);

          await expectLater(future, throwsA(42));
        });

        test(
          'after manually going back to loading, dispose throws StateError',
          () async {
            final container = createContainer();
            final completer = Completer<int>.sync();
            final provider = factory.simpleTestProvider<int>(
              (ref) => completer.future,
            );

            container.read(provider);
            container.read(provider.notifier).state = const AsyncData(42);
            container.read(provider.notifier).state = const AsyncLoading<int>();

            final future = container.read(provider.future);

            container.dispose();

            completer.complete(42);

            await expectLater(future, throwsStateError);
          },
        );

        test(
            'resolves with the new state if AsyncNotifier.state is modified during loading',
            () async {
          final container = createContainer();
          final completer = Completer<int>.sync();
          final provider = factory.simpleTestProvider<int>(
            (ref) => completer.future,
          );
          final listener = Listener<Future<int>>();

          final sub = container.listen(provider.notifier, (previous, next) {});
          container.listen(provider.future, listener);

          expect(sub.read().future, completion(21));

          sub.read().state = const AsyncData(21);

          completer.complete(42);

          expect(sub.read().future, completion(21));
          verifyZeroInteractions(listener);
        });

        test('resolves with the new state when notifier.state is changed',
            () async {
          final container = createContainer();
          final provider = factory.simpleTestProvider<int>((ref) => 0);
          final listener = Listener<Future<int>>();

          final sub = container.listen(provider.notifier, (previous, next) {});
          container.listen(provider.future, listener, fireImmediately: true);

          expect(sub.read().future, SynchronousFuture<int>(0));
          verifyOnly(listener, listener(null, SynchronousFuture<int>(0)));

          sub.read().state = const AsyncData(1);

          expect(sub.read().future, SynchronousFuture<int>(1));
        });

        test('retuns a Future identical to that of .future', () {
          final listener = OnBuildMock();
          final dep = StateProvider((ref) => 0);
          final provider = factory.simpleTestProvider<int>(
            (ref) {
              listener();
              return Future.value(ref.watch(dep));
            },
          );
          final container = createContainer();

          container.listen(provider.notifier, (previous, next) {});
          final notifier = container.read(provider.notifier);

          expect(notifier.future, same(container.read(provider.future)));
        });

        test(
            'when read on outdated provider, refreshes the provider and return the up-to-date state',
            () async {
          final listener = OnBuildMock();
          final dep = StateProvider((ref) => 0);
          final provider = factory.simpleTestProvider<int>(
            (ref) {
              listener();
              return Future.value(ref.watch(dep));
            },
          );
          final container = createContainer();

          container.listen(provider, (previous, next) {});
          final notifier = container.read(provider.notifier);

          expect(await container.read(provider.future), 0);
          verify(listener()).called(1);

          container.read(dep.notifier).state++;

          expect(notifier.future, notifier.future);
          expect(notifier.future, same(container.read(provider.future)));
          expect(await notifier.future, 1);
          verify(listener()).called(1);
        });
      });

      group('AsyncNotifierProvider.notifier', () {
        test(
            'never emits an update. The Notifier is never recreated once it is instantiated',
            () async {
          final listener = OnBuildMock();
          final dep = StateProvider((ref) => 0);
          final provider = factory.testProvider<int>(() {
            listener();
            return factory.notifier((ref) => ref.watch(dep));
          });
          final container = createContainer();

          container.listen(provider, (previous, next) {});
          final notifier = container.read(provider.notifier);

          verify(listener()).called(1);
          expect(container.read(provider), const AsyncData(0));

          container.read(dep.notifier).state++;

          expect(container.read(provider), const AsyncData(1));
          expect(container.read(provider.notifier), same(notifier));
          verifyNoMoreInteractions(listener);
        });
      });

      test(
          'Can override AsyncNotifier.updateShouldNotify to change the default filter logic',
          () {
        final provider = factory.simpleTestProvider<Equal<int>>(
          (ref) => Equal(42),
          updateShouldNotify: (a, b) => a != b,
        );
        final container = createContainer();
        final listener = Listener<AsyncValue<Equal<int>>>();

        container.listen(provider, listener);
        final notifier = container.read(provider.notifier);
        notifier.state = notifier.state;

        verifyZeroInteractions(listener);

        notifier.state = AsyncData(Equal(42));

        verifyZeroInteractions(listener);

        notifier.state = AsyncData(Equal(21));

        verifyOnly(
          listener,
          listener(AsyncData(Equal(42)), AsyncData(Equal(21))),
        );
      });

      group('AsyncNotifer.update', () {
        test('passes in the latest state', () async {
          final container = createContainer();
          final provider = factory.simpleTestProvider<int>(
            (ref) => 0,
          );

          final sub = container.listen(provider.notifier, (prev, next) {});

          expect(
            container.read(provider),
            const AsyncData<int>(0),
          );

          await expectLater(
            sub.read().update((prev) => prev + 1),
            completion(1),
          );
          await expectLater(
            sub.read().future,
            completion(1),
          );
          await expectLater(
            sub.read().update((prev) => prev + 1),
            completion(2),
          );
        });

        test('can specify onError to handle error scenario', () async {
          final container = createContainer();
          final provider = factory.simpleTestProvider<int>(
            (ref) => Error.throwWithStackTrace(42, StackTrace.empty),
          );
          var callCount = 0;
          Object? actualErr;
          Object? actualStack;

          final sub = container.listen(provider.notifier, (prev, next) {});

          expect(
            container.read(provider),
            const AsyncError<int>(42, StackTrace.empty),
          );

          await expectLater(
            sub.read().update(
              (prev) {
                callCount++;
                return prev;
              },
              onError: (err, stack) {
                actualErr = err;
                actualStack = stack;
                return 21;
              },
            ),
            completion(21),
          );
          expect(callCount, 0);
          expect(actualErr, 42);
          expect(actualStack, StackTrace.empty);
          expect(container.read(provider), const AsyncData(21));
        });

        test(
            'executes immediately with current state if a state is avalailable',
            () async {
          final container = createContainer();
          final provider = factory.simpleTestProvider<int>((ref) => 1);

          final sub = container.listen(provider.notifier, (prev, next) {});

          expect(container.read(provider), const AsyncData(1));

          await expectLater(
            sub.read().update((prev) => prev + 1),
            completion(2),
          );
          expect(container.read(provider), const AsyncData(2));
        });

        test(
            'executes immediately with current state if an error is avalailable',
            () async {
          final container = createContainer();
          final provider = factory.simpleTestProvider<int>(
            (ref) => Error.throwWithStackTrace(42, StackTrace.empty),
          );
          var callCount = 0;

          final sub = container.listen(provider.notifier, (prev, next) {});

          expect(
            container.read(provider),
            const AsyncError<int>(42, StackTrace.empty),
          );

          await expectLater(
            sub.read().update((prev) {
              callCount++;
              return prev + 1;
            }),
            throwsA(42),
          );

          expect(callCount, 0);
          expect(
            container.read(provider),
            const AsyncError<int>(42, StackTrace.empty),
          );
        });

        test('awaits the future resolution if in loading state', () async {
          final container = createContainer();
          final provider = factory.simpleTestProvider<int>(
            (ref) => Future.value(42),
          );

          final sub = container.listen(provider.notifier, (prev, next) {});

          expect(container.read(provider), const AsyncLoading<int>());

          await expectLater(
            sub.read().update((prev) => prev + 1),
            completion(43),
          );
          expect(container.read(provider), const AsyncData(43));
        });
      });
    });
  }

  group('AutoDispose variant', () {
    test('can watch autoDispose providers', () {
      final dep = Provider.autoDispose((ref) => 0);
      final provider = AutoDisposeAsyncNotifierProvider<
          AutoDisposeAsyncTestNotifier<int>, int>(
        () => AutoDisposeAsyncTestNotifier((ref) {
          return ref.watch(dep);
        }),
      );
      final container = createContainer();

      expect(container.read(provider), const AsyncData(0));
    });
  });

  group('modifiers', () {
    void canBeAssignedToAlwaysAliveRefreshable<T>(
      AlwaysAliveRefreshable<T> provider,
    ) {}

    void canBeAssignedToRefreshable<T>(
      Refreshable<T> provider,
    ) {}

    void canBeAssignedToAlwaysAliveListenable<T>(
      AlwaysAliveProviderListenable<T> provider,
    ) {}

    void canBeAssignedToProviderListenable<T>(
      ProviderListenable<T> provider,
    ) {}

    // TODO use package:expect_error to test that commented lined are not compiling

    test('provider', () {
      final provider = AsyncNotifierProvider<AsyncTestNotifier<int>, int>(
        () => AsyncTestNotifier((ref) => 0),
      );

      provider.select((AsyncValue<int> value) => 0);
      provider.selectAsync((int value) => 0);

      canBeAssignedToProviderListenable<AsyncValue<int>>(provider);
      canBeAssignedToAlwaysAliveListenable<AsyncValue<int>>(provider);
      canBeAssignedToRefreshable<AsyncValue<int>>(provider);
      canBeAssignedToAlwaysAliveRefreshable<AsyncValue<int>>(provider);

      canBeAssignedToProviderListenable<Future<int>>(provider.future);
      canBeAssignedToAlwaysAliveListenable<Future<int>>(provider.future);
      canBeAssignedToRefreshable<Future<int>>(provider.future);
      canBeAssignedToAlwaysAliveRefreshable<Future<int>>(provider.future);

      canBeAssignedToProviderListenable<AsyncNotifier<int>>(provider.notifier);
      canBeAssignedToAlwaysAliveListenable<AsyncNotifier<int>>(
        provider.notifier,
      );
      canBeAssignedToRefreshable<AsyncNotifier<int>>(provider.notifier);
      canBeAssignedToAlwaysAliveRefreshable<AsyncNotifier<int>>(
        provider.notifier,
      );
    });

    test('autoDispose', () {
      final autoDispose = AsyncNotifierProvider.autoDispose<
          AutoDisposeAsyncTestNotifier<int>, int>(
        () => AutoDisposeAsyncTestNotifier((ref) => 0),
      );

      autoDispose.select((AsyncValue<int> value) => 0);
      autoDispose.selectAsync((int value) => 0);

      canBeAssignedToProviderListenable<AsyncValue<int>>(autoDispose);
      // canBeAssignedToAlwaysAliveListenable<AsyncValue<int>>(autoDispose);
      canBeAssignedToRefreshable<AsyncValue<int>>(autoDispose);
      // canBeAssignedToAlwaysAliveRefreshable<AsyncValue<int>>(autoDispose);

      canBeAssignedToProviderListenable<Future<int>>(autoDispose.future);
      // canBeAssignedToAlwaysAliveListenable<Future<int>>(autoDispose.future);
      canBeAssignedToRefreshable<Future<int>>(autoDispose.future);
      // canBeAssignedToAlwaysAliveRefreshable<Future<int>>(autoDispose.future);

      canBeAssignedToProviderListenable<AutoDisposeAsyncNotifier<int>>(
        autoDispose.notifier,
      );
      // canBeAssignedToAlwaysAliveListenable<AutoDisposeAsyncNotifier<int>>(
      //   autoDispose.notifier,
      // );
      canBeAssignedToRefreshable<AutoDisposeAsyncNotifier<int>>(
        autoDispose.notifier,
      );
      // canBeAssignedToAlwaysAliveRefreshable<AutoDisposeAsyncNotifier<int>>(
      //   autoDispose.notifier,
      // );
    });

    test('family', () {
      final family = AsyncNotifierProvider.family<
          AsyncTestNotifierFamily<String>, String, int>(
        () => AsyncTestNotifierFamily((ref) => '0'),
      );

      family(0).select((AsyncValue<String> value) => 0);
      family(0).selectAsync((String value) => 0);

      canBeAssignedToProviderListenable<AsyncValue<String>>(family(0));
      canBeAssignedToAlwaysAliveListenable<AsyncValue<String>>(family(0));
      canBeAssignedToRefreshable<AsyncValue<String>>(family(0));
      canBeAssignedToAlwaysAliveRefreshable<AsyncValue<String>>(family(0));

      canBeAssignedToProviderListenable<Future<String>>(family(0).future);
      canBeAssignedToAlwaysAliveListenable<Future<String>>(family(0).future);
      canBeAssignedToRefreshable<Future<String>>(family(0).future);
      canBeAssignedToAlwaysAliveRefreshable<Future<String>>(family(0).future);

      canBeAssignedToProviderListenable<FamilyAsyncNotifier<String, int>>(
        family(0).notifier,
      );
      canBeAssignedToAlwaysAliveListenable<FamilyAsyncNotifier<String, int>>(
        family(0).notifier,
      );
      canBeAssignedToRefreshable<FamilyAsyncNotifier<String, int>>(
        family(0).notifier,
      );
      canBeAssignedToAlwaysAliveRefreshable<FamilyAsyncNotifier<String, int>>(
        family(0).notifier,
      );
    });

    test('autoDisposeFamily', () {
      expect(
        AsyncNotifierProvider.autoDispose.family,
        same(AsyncNotifierProvider.family.autoDispose),
      );

      final autoDisposeFamily = AsyncNotifierProvider.autoDispose
          .family<AutoDisposeAsyncTestNotifierFamily<String>, String, int>(
        () => AutoDisposeAsyncTestNotifierFamily((ref) => '0'),
      );

      autoDisposeFamily(0).select((AsyncValue<String> value) => 0);
      autoDisposeFamily(0).selectAsync((String value) => 0);

      canBeAssignedToProviderListenable<AsyncValue<String>>(
        autoDisposeFamily(0),
      );
      // canBeAssignedToAlwaysAliveListenable<AsyncValue<String>>(
      //   autoDisposeFamily(0),
      // );
      canBeAssignedToRefreshable<AsyncValue<String>>(
        autoDisposeFamily(0),
      );
      // canBeAssignedToAlwaysAliveRefreshable<AsyncValue<String>>(
      //   autoDisposeFamily(0),
      // );

      canBeAssignedToProviderListenable<Future<String>>(
        autoDisposeFamily(0).future,
      );
      // canBeAssignedToAlwaysAliveListenable<Future<String>>(
      //   autoDisposeFamily(0).future,
      // );
      canBeAssignedToRefreshable<Future<String>>(
        autoDisposeFamily(0).future,
      );
      // canBeAssignedToAlwaysAliveRefreshable<Future<String>>(
      //   autoDisposeFamily(0).future,
      // );

      canBeAssignedToProviderListenable<
          AutoDisposeFamilyAsyncNotifier<String, int>>(
        autoDisposeFamily(0).notifier,
      );
      // canBeAssignedToAlwaysAliveListenable<
      //     AutoDisposeFamilyAsyncNotifier<String, int>>(
      //   autoDisposeFamily(0).notifier,
      // );
      canBeAssignedToRefreshable<AutoDisposeFamilyAsyncNotifier<String, int>>(
        autoDisposeFamily(0).notifier,
      );
      // canBeAssignedToAlwaysAliveRefreshable<
      //     AutoDisposeFamilyAsyncNotifier<String, int>>(
      //   autoDisposeFamily(0).notifier,
      // );
    });
  });
}

@immutable
class Equal<T> {
  // ignore: prefer_const_constructors_in_immutables
  Equal(this.value);

  final T value;

  @override
  bool operator ==(Object other) => other is Equal<T> && other.value == value;

  @override
  int get hashCode => Object.hash(runtimeType, value);
}

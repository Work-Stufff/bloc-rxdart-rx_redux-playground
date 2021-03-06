import 'dart:async';

import 'package:built_collection/built_collection.dart';
import 'package:disposebag/disposebag.dart';
import 'package:distinct_value_connectable_observable/distinct_value_connectable_observable.dart';
import 'package:flutter_bloc_pattern/flutter_bloc_pattern.dart';
import 'package:meta/meta.dart';
import 'package:rxdart/rxdart.dart';
import 'package:simple_todo/domain/todo.dart';
import 'package:simple_todo/domain/todo_repo.dart';
import 'package:tuple/tuple.dart';

// ignore_for_file: close_sinks

enum Filter { onlyCompleted, onlyIncomplete, all }

titleFor({@required Filter filter}) {
  switch (filter) {
    case Filter.onlyCompleted:
      return 'Only completed';
    case Filter.onlyIncomplete:
      return 'Only incomplete';
    case Filter.all:
      return 'All';
  }
}

class HomeBloc implements BaseBloc {
  ///
  /// Output streams
  ///
  final ValueObservable<BuiltList<Todo>> todos$;
  final ValueObservable<Filter> filter$;

  ///
  /// Input functions
  ///
  final void Function(Todo, bool) toggleCompleted;
  final void Function(Todo) delete;
  final void Function(Filter) changeFilter;

  ///
  /// Dispose
  ///
  final void Function() _dispose;

  HomeBloc._(
    this._dispose, {
    @required this.todos$,
    @required this.toggleCompleted,
    @required this.delete,
    @required this.filter$,
    @required this.changeFilter,
  });

  @override
  void dispose() => _dispose();

  factory HomeBloc(TodoRepo todoRepo) {
    final toggleCompletedSubject = PublishSubject<Tuple2<Todo, bool>>();
    final deleteSubject = PublishSubject<Todo>();
    final filterSubject = BehaviorSubject.seeded(Filter.all);

    /// Output state stream
    final todos$ = publishValueSeededDistinct(
      Observable.combineLatest2(
        todoRepo.allTodo().distinct(),
        filterSubject.distinct(),
        (BuiltList<Todo> todos, Filter filter) {
          switch (filter) {
            case Filter.onlyCompleted:
              return BuiltList.of(todos.where((todo) => todo.completed));
            case Filter.onlyIncomplete:
              return BuiltList.of(todos.where((todo) => !todo.completed));
            case Filter.all:
              return todos;
          }
          return todos;
        },
      ),
      seedValue: null, // loading state
    );

    ///
    /// Throttle time
    ///
    final toggleCompleted$ = toggleCompletedSubject
        .groupBy((tuple) => tuple.item1.id)
        .map((g) => g.throttleTime(const Duration(milliseconds: 600)))
        .flatMap((g) => g);

    final bag = DisposeBag(
      [
        // Listen toggle
        (toggleCompleted$.switchMap(
          (tuple) async* {
            final updated =
                tuple.item1.rebuild((b) => b.completed = tuple.item2);
            yield await todoRepo.update(updated);
          },
        ).listen((result) => print('[HOME_BLOC] toggle=$result'))),
        // Listen delete
        deleteSubject.flatMap(
          (todo) {
            return Observable.defer(
              () => Stream.fromFuture(todoRepo.delete(todo)),
            );
          },
        ).listen((result) => print('[HOME_BLOC] delete=$result')),
        // Listen todos
        todos$.listen(
            (todos) => print('[HOME_BLOC] todos.length=${todos?.length}')),
        // Connect
        todos$.connect(),
        // controllers
        toggleCompletedSubject,
        deleteSubject,
        filterSubject,
      ],
    );

    return HomeBloc._(
      bag.dispose,
      // Outputs
      todos$: todos$,
      filter$: filterSubject,
      // Inputs
      changeFilter: filterSubject.add,
      toggleCompleted: (todo, newValue) =>
          toggleCompletedSubject.add(Tuple2(todo, newValue)),
      delete: deleteSubject.add,
    );
  }
}

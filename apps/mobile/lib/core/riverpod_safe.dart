import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Diffère une écriture Riverpod après le frame courant.
///
/// Évite l'erreur « Tried to modify a provider while the widget tree was building »
/// (flush, bootstrap, listen, navigation).
void scheduleProviderWrite(void Function() write) {
  final phase = SchedulerBinding.instance.schedulerPhase;
  if (phase == SchedulerPhase.idle ||
      phase == SchedulerPhase.postFrameCallbacks) {
    Future.microtask(write);
    return;
  }
  SchedulerBinding.instance.addPostFrameCallback((_) => write());
}

void bumpStateProvider(StateController<int> controller) {
  scheduleProviderWrite(() => controller.state++);
}

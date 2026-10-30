# Desktop service lifetime

The desktop host registers native executions first and workspace files second.
Its services record carries the resolved configuration and the run's Logger.
Proton's application task group supervises the host task; `start` waits until
both services are ready before renderer commands can use them.

`Controller.shutdown` requests the public `Embedder` stop reason and awaits the
framework outcome. Reverse cleanup revokes file access before it waits for
native execution shutdown. Repeated and concurrent shutdown callbacks use one
confirmed outcome. A startup failure stops only services that started and wakes
the readiness waiter with the original failure.

The Proton adapter calls shutdown from `on_shutdown`. Its existing quit guard
can finish the same shutdown earlier so an unconfirmed child exit still prevents
quit. The repeated lifecycle callback is safe. Wire frames, native caller grants
and renderer authority remain owned by the existing native bridge.

Run `moon test pkgs/morphir-workbench-native/hosting --target native` to verify
an active execution ends before process cleanup completes, reverse service
order, repeated shutdown and startup failure. The packaged desktop lifecycle
suite exercises the actual Proton callbacks and native workers.

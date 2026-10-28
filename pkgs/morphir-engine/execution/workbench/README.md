# Workbench execution boundary

The pure host boundary decodes a private command's `op` once into a closed request and sends it through
Moon-Lander's synchronous mediator. The owning handler retains payload validation, capability verification
and session state changes. Scheme submissions use a closed operation type through selection, reservation
and claim handling.

This routing is internal. Existing operation names, closed payload shapes, failure codes, receipt versions
and public `Host.handle` replies remain unchanged. Unknown names fail with `workbench.host_operation` before
payload processing. The package imports the pure mediator only and runs on native, JS, WASI and Wasm GC.

Run `moon test pkgs/morphir-engine/execution/workbench --target <target>` for the boundary refusal and host
continuity regression. `moon test apps/morphir-workbench/executions --target <target>` exercises the existing
JSON/Ion, Scheme, native-policy and HTTP-policy bridge contracts through the same sender.

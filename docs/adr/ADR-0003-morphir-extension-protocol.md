---
status: proposed
---

# ADR-0003: Use a transport-independent JSON-RPC protocol for extensions

Morphir hosts will call independently packaged extensions through the versioned Morphir Extension Protocol. The protocol uses JSON-RPC 2.0, passes source documents and artifacts by value, and negotiates capabilities before use. Native executable extensions use `Content-Length` framed standard input and output first. HTTP, local sockets, and WASM bindings may carry the same logical messages later. This keeps the CLI independent of extension language and location while leaving filesystem, network, output, and process policy with the host.

We rejected a CLI-specific command protocol because editors, daemons, and tests need the same operations. We also rejected host file paths as the primary input because they do not work for unsaved documents, sandboxes, or remote extensions. Direct library linking remains available for built-in code, but it is not the portable extension boundary.

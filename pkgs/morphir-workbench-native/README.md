# Native Workbench workers

The native host owns the existing Workbench job owner and starts its own packaged
executable in worker mode. Renderer input cannot select executable paths, arguments
or environment variables. Only typed evaluation runs in the child.

Each child receives one big-endian 32-bit length-prefixed UTF-8 JSON request and
returns one frame of terminal evidence. Both frames are limited to 1 MiB. Stderr
is drained with a 64 KiB limit. The host observes resident memory every 20 ms,
cancels a worker above 256 MiB or after 30 seconds, and waits for exit before
publishing terminal evidence. Resident-memory sampling is an observed process
budget, with possible overshoot between samples, rather than an allocation cap.

At most two workers execute concurrently. The shared owner retains its eight-job,
16 MiB evidence limits and admits each execution claim once. Returned outcomes
survive late cancellation; cleanup failures remain separate evidence. Failure to
confirm exit keeps the job nonterminal and prevents further execution claims.

The native service has macOS and Linux process acceptance. Packaged Proton job
discovery is enabled on macOS Apple Silicon. Linux and Windows retain browser
workers until their packaged GUI/lifecycle lanes are independently qualified.
The private bridge does not advertise the proposed public Morphir native profile.

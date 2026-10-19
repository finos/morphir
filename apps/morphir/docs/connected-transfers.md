# Save connected generated artifacts

Select an authenticated Workbench host that advertises the exact
`morphir/workbench/artifacts` `0.1.0-draft.1` service. Use Node 24 on POSIX, or a
native POSIX CLI with its maintained Node 24 helper. Windows private credential
protection is unavailable in this binding. Portable Wasm and Wasm GC explicitly refuse it.
Terminal setup uses the host's one-use launch URL through a private input file or
stdin; it does not need a browser or UI assets.

```sh
morphir connected connect launch.txt --provider workbench-http \
  --connection connection.json --connection-scope artifacts --json
morphir connected artifacts request.json --provider workbench-http \
  --connection connection.json --output saved --json
```

The connection file is private to its owner. Protect it as a credential. The CLI
never places its cookie or the one-use launch token in process arguments or
reports. The destination connection file must not already exist. Artifact setup
selects exactly one advertised provider; execution setup remains the default
`--connection-scope executions` and has its separate descriptor.

The request has exactly these fields:

```json
{
  "providerId": "playground",
  "target": "your-negotiated-target",
  "irVersion": "4.0.0",
  "ir": {},
  "options": {}
}
```

Supply the actual IR accepted by that selected producer. This command consumes
generated artifacts; it does not silently compile source, select another
provider, or use a legacy artifact representation. A file or `-` for stdin is
bounded to a complete 1 MiB UTF-8 request.

Every file in the captured inventory must pass its exact length and SHA-256
checks, and the owning generation must be released, before any bytes become
eligible for publication. The limits are 256 files, 16 MiB per file and 64 MiB
per generation. Empty files and binary/NUL bytes retain their exact content.

The CLI saves the complete verified inventory to `saved/artifacts` using its
current content publisher. It refuses an existing artifact destination and
checks again under the publication lock. A successful report says
`"publication":"cli"`; it does not claim the host published files. Remote
retention, local scratch and local publication have separate owners.

`--timeout` bounds acquisition in milliseconds (default 120000, maximum 600000).
SIGINT or `--cancel-file` discards the attempt. Closing the dedicated connection
cleans only its owning remote retention; a missing reply is reported as a closed
connection with uncertain retention identity rather than a confirmed release.
There is no implicit resubmission, reconnect to another owner, or profile
fallback. Each invocation freshly authenticates and checks the pinned session
and exact provider offer.

Exit status 0 means publication succeeded after verification and release; 1
means a transfer, publication, cleanup or timeout failure; 2 means a refused
request/setup; and 130 means interruption. Reports retain the cleanup outcome.

Connected original models remain blocked on the separately owned exact
model-original service. Artifact bytes, model projections and MEP generation
capabilities do not grant original-model access. The local model commands retain
their existing captured-original behavior.

# Shared artifact consumer

`EXTRACTION.json` pins the unchanged application-independent transfer attempt,
verified-byte owner, RPC channel and their focused tests from published PR147
revision `4ce0f57a84f58fad3106d0de18105eeadf0822f9`. The nested `artifact-client`
directory is the exact maintained upstream boundary; its `SOURCE.json`, SHA-256
inventory and Apache/Unicode notices remain unchanged. Its dependency is the
pinned `@std/semver` alias declared at the repository root.

The CLI adds authenticated socket effects and explicit local publication.
`selection.mts` selects the exact advertised profile through the existing
selector. It does not grant authority from a different capability or downgrade
profiles. No second digest, path, literal decoder or transfer state machine lives
in the CLI helper.

PR147 landed as `47fa644`. Workbench's transfer, verified-byte and RPC modules,
including its nested boundary imports, re-export these shared modules. Both
applications use the same branded values and consumer lifecycle.
`scripts/artifact-client-source.mbtx` verifies the canonical nested source here.
The nested README is retained byte-exactly as historical upstream documentation;
its `SOURCE.json` records the verified merged pin and remains authoritative.

Run the focused regressions with:

```sh
node --test pkgs/morphir-host/artifact-client/artifact-transfer.test.ts \
  pkgs/morphir-host/artifact-client/verified-artifacts.test.ts \
  pkgs/morphir-host/artifact-client/artifact-rpc.test.ts
```

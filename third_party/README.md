# CLI dependencies

`Yoorkin/ArgParser` 0.2.1 and its dependency `Yoorkin/trie` 0.2.10 are local workspace members. Their latest published archives still use JSON manifests, which MoonBit 0.10.15 rejects. Local copies keep the existing CLI parser behavior while allowing a fresh checkout to build without modifying the package cache.

The source archives, SHA-256 digests and licenses are recorded in [dependencies.json](dependencies.json). Both archives declare Apache-2.0. Each directory includes that license, its original README and upstream tests. The changes are limited to the compiler formatter's manifest migration and source formatting. The trie README tests use Debug to retain their quoted string expectations under the new core.

Refresh these copies from verified Mooncakes archives. Remove the workspace overrides when upstream publishes compatible manifests, then run the CLI and installed-package tests before switching back to registry dependencies.

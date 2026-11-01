# Proposal

## Why

The MoonBit CLI is becoming the main Morphir CLI, because the same code can also run in the browser. Its extension
story is not ready for that role:

- Language frontends are compiled into the binary. `apps/morphir` imports the Elm frontend
  (`finos/morphir-engine/elm`) and the MoonBit frontend (`finos/morphir-engine/moonbit`). Every frontend change rebuilds
  the CLI, and we get little of the value of the extension protocol we defined.
- Extension acquisition is not MoonBit. `extension repository|bundle|install|update|uninstall|search|list` delegate to
  a Rust native-services helper that links the shared `morphir-distribution` library. That helper needs explicit pin
  and helper flags, supports local-directory repositories only, and cannot run in the browser. The Rust CLI that owns
  that library is being sunset.
- There is no remote acquisition at all. Extensions already ship from their own repositories as GitHub releases
  (finos/morphir-python, finos/morphir-elm), but a user must download each bundle, create a local repository, publish
  into it and install from it. Nobody can host their own set of extensions for others.
- Installed extensions are not used by invocation (`morphir-ukvn.5.64.30`), so a compile cannot find a provider that
  is not built in.

We want an experience like coursier channels and like npm or PyPI publishing: repositories that anyone can host on
GitHub and a default path that is short for both users and publishers. This change is the MVP pipeline. Trust
decisions and verification of signed releases follow in `add-extension-trust`, so the rest of the work is not
blocked on them.

## What Changes

- **Acquisition in MoonBit.** Resolution, download, digest checks, the install probe, the content-addressed store,
  the installed catalog and locks move into MoonBit. The extension lifecycle commands stop delegating to the Rust
  native-services helper and stop requiring `--services-pin` and `--services-helper`.
- **GitHub-hosted repositories.** A repository owner keeps an index on a protected branch or Pages site of a GitHub
  repository. Index entries point at publisher releases and name the publisher identity that must have signed them.
  The CLI ships with the `finos` repository configured and enabled. Local-directory repositories keep working.
- **Capability lookup.** The CLI can ask its enabled repositories which extensions provide a capability (for example
  `frontend.compile` for `elm` at IR 4), not only look up an extension by name.
- **No trust step in the MVP.** Enabling a repository is the user's choice to use it. Installation checks digests and
  probes claims, but asks for no trust decision and verifies no signatures. `add-extension-trust` adds `morphir trust`,
  trust prompts and Sigstore verification of GitHub artifact attestations as a fast follower. Normal runs stay
  offline.
- **On-demand install.** When a compile or generate needs a provider that is not installed, the CLI looks it up in
  the repositories, offers it, installs it and continues.
- **`morphir setup`.** A guided flow installs the repository's recommended extensions, plus what the workspace's
  configuration needs. "Customize" opens a capability view with a provider choice per language. A review screen
  confirms the selection. Flags replace the screens for CI.
- **Publishing.** `morphir extension publish` runs in a publisher's release workflow and creates a GitHub release,
  with GitHub artifact attestations so that `add-extension-trust` can verify them later. The repository owner's index
  workflow admits new releases from registered publisher repositories. Setup commands generate both workflows.
- **BREAKING**: the Elm and MoonBit frontends leave the CLI binary. They are installed from the `finos` repository,
  on first use or through `morphir setup`. Their code moves to the repositories that own the languages (Elm to
  finos/morphir-elm); that move is tracked separately.
- **BREAKING**: the CLI keeps `MORPHIR_HOME` but uses a new, versioned layout for extension state. It does not read
  or delete extension state that the Rust CLI wrote; extensions are installed again.

## Capabilities

### New Capabilities

- `extensions/repositories`: configuring, enabling and reading extension repositories (GitHub-hosted and local),
  their index content, freshness, search and capability lookup.
- `extensions/installation`: resolving, downloading, checking, probing, storing, recording, updating and removing
  extensions under `MORPHIR_HOME`, and offline activation.
- `extensions/provider-acquisition`: how a compile or generate obtains a provider it does not have, including the
  frontends that are no longer built in.
- `extensions/setup`: the `morphir setup` flow and its unattended form.
- `extensions/publishing`: how a publisher releases an extension and how a repository owner admits it into an index.

### Modified Capabilities

None. No capability has a main spec in `openspec/specs/` yet.

## Beads

- **Tracked by**: `morphir-ukvn.5.64.34`
- **Related**:
  - the follow-up change `add-extension-trust` (trust and Sigstore verification, the fast follower)
  - the MEP worker host change being planned in worktree `mep-worker-host` (this change waits on it)
  - `morphir-ukvn.5.64` (parent: the MoonBit CLI becomes the primary Morphir CLI)
  - `morphir-ukvn.5.64.30` (joining installed extensions to invocation; this change delivers that join)
  - `morphir-ukvn.5.99` (Moon-Lander adoption; configuration, hosting and logging this change builds on)
  - `morphir-ukvn.1.10.5` and `morphir-ukvn.5.55.9` (MoonBit extension packaging and installed qualification; they
    become consumers of this acquisition path)
  - `morphir-ukvn.5.22` (Elm frontend; its code moves out of this repository)
  - `morphir-ukvn.1.4` and `morphir-ukvn.1.8` (Gleam and Elm-native moves; their "built in by pin" plans are
    superseded by repository installation)
  - `morphir-ds9e.6` (Rust CLI setup hardening; this change defines `morphir setup` for the MoonBit CLI instead)

## Impact

- **Code:** `apps/morphir` (extension commands, the new `setup` command, provider selection in compile and
  generate), `pkgs/morphir-host` (home layout, filesystem and HTTP edges), a new MoonBit acquisition package, and
  removal of the frontend imports from `apps/morphir/moon.pkg`. The native-services helper loses its distribution
  role.
- **Dependencies:** the MEP worker host being planned in this repository (worktree `mep-worker-host`), which runs
  probes and installed extensions without user-supplied helpers; Moon-Lander configuration and hosting from
  `adopt-moon-lander`. The Sigstore verifier in moonrockz/moon-lander is needed only by `add-extension-trust`.
- **Other repositories:** finos/morphir hosts the `finos` repository index and its admission workflow. Publisher
  repositories (finos/morphir-elm, finos/morphir-gleam, finos/morphir-python and others) add `morphir extension
  publish` to their release workflows.
- **Users:** the first Elm or MoonBit compile installs a frontend, or `morphir setup` does it ahead of time.
  Extensions installed by the Rust CLI are not reused.
- **Browser:** the browser can read GitHub-hosted indexes but cannot download GitHub release assets (no CORS
  headers). Browser installs need the owner to mirror admitted artifacts on a CORS-enabled host.

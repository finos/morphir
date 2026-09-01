---
title: Morphir Playground
sidebar_label: Playground
sidebar_position: 4
---

# Morphir Playground

**Status:** Active.

This proposal brings the capability of morphir-elm's try-morphir page into
this repository and extends it. try-morphir compiles Elm to Morphir IR in
the browser and renders the result; the frontend and the absence of a
backend are both fixed at build time. The Playground makes both choices at
run time, driven by the frontends and targets that installed extensions and
builtins actually advertise.

The work spans three repositories. `ecosystem/morphir-rust` gains the
installed-frontend metadata the catalog reads. This repository gains three
protocol methods, a playground provider, and the `morphir playground`
command.
[finos/morphir-ui](https://github.com/finos/morphir-ui) gains a pipeline
service, a playground view, and a shared code editor component.

## What this design establishes

A user opens the Playground, picks a frontend, types source, compiles it to
Morphir IR, inspects the IR through the existing Insight and XRay views, then
picks a target and generates artifacts. The frontend and target lists come
from one catalog projected from the CLI's extension registry, which carries
built-in and installed providers alike. Target choices incompatible with the
selected frontend's
IR versions are disabled with the reason shown.

Nothing the Playground does writes to the filesystem. Generated artifacts
return in the response and the view offers them as downloads.

## Background: what already exists

Four pieces are already built, and the design is shaped by them.

The Morphir Extension Protocol carries everything the pipeline needs.
`CompileRequest` already accepts `documents: Vec<SourceDocument>` with an
`options.irVersion`, and `CompileResult` returns `{ir, irVersion}`, which
feeds `GenerateRequest {ir, target, options}` unchanged. The whole pipeline
composes in memory. No step needs a file.

Backend capability metadata is already machine readable without starting an
extension. A schema-v2 release record carries a `BackendRecord` with
`targets`, `irVersions`, and a `generate` flag, which is how
`crates/morphir/src/commands/generate/provider.rs` validates a live session
against an installed record.

Frontends are not symmetric, and closing that gap is part of this work. Over
MEP a frontend negotiates a `FrontendCapability` carrying `languages` (each
with an `id` and `fileExtensions`), `irVersions`, and a `compile` flag, but
an installed release record stores only the `Capability::Frontend` marker.
The languages and IR versions of an installed frontend are therefore
unknowable without launching it. `morphir-distribution` gains a
`FrontendRecord` so the catalog can list installed frontends without
starting anything.

The record mirrors the whole `FrontendCapability`: the IR versions, the
`compile`, `incremental`, and `fragments` flags, and a `LanguageRecord` per
language carrying that language's id and its file extensions. Keeping the
extensions attached to their language is what lets the Playground map an
editor buffer to a frontend, and lets the code editor choose a syntax mode,
without launching anything. The wire type refuses unknown fields, so a
narrower record would have cost another schema version to widen later.

The record arrives with index schema version 3, following how version 2
introduced backend metadata. A schema-v3 record that declares the frontend
capability must carry frontend metadata, and must not carry it otherwise,
which are the rules version 2 already applies to backends. Records at
version 1 and 2 stay readable. A frontend from one of those contributes a
catalog entry whose languages are undeclared, and the Playground lists it as
selectable but unlabeled rather than hiding it. An optional field on
version 2 would have avoided the version bump, but it would also contradict
the requirement version 2 states for backends, leaving two different rules
for the same idea.

The loopback UI host in `crates/morphir/src/commands/ui/` serves the web app
over a session-authenticated localhost binding, with a JSON-RPC websocket, a
`SessionManifest`, and typed `ConnectedMethod` dispatch.

finos/morphir-ui carries the connected client and the visualization. Its
`ConnectedRpcClient.call<A, I>(method, params, schema)` is generic over
method and Effect Schema and already handles reconnection, notifications,
and request size limits. `InsightView` and `XRayView` render Morphir IR
today.

ADR-0004 closes with the observation that this repository publishes no
browser-accessible Morphir UI until finos/morphir-ui ships a hosted web
build. The Playground is the first feature that gives that hosted build a
reason to exist, which is why the design keeps a browser implementation
reachable rather than assuming a CLI is present.

## Provider catalog

The Playground does not decide which provider serves a language or a target.
`crates/morphir/src/extensions.rs` builds an `ExtensionRegistry` carrying the
built-in providers plus everything `list_installed` reports, and that
registry resolves a language and IR release to one provider — preferring an
installed provider over a built-in offering the same thing, and refusing an
ambiguous pair. `morphir compile` and `morphir generate` resolve through it,
and so does the Playground, so a language the CLI can compile is a language
the Playground can compile.

`morphir.playground.catalog` is therefore a projection, not a second source
of truth. It walks `ExtensionRegistry::providers()` and reports, per
language and per target, what that provider advertises: the language id and
its file extensions, the IR versions, the `compile`, `incremental`, and
`fragments` flags for a frontend, the `generate` flag for a backend, and the
provider's id, name, version, origin, and invocation mode. Reading installed
frontend metadata without launching anything depends on the `FrontendRecord`
described above.

The catalog's entries are ordered installed-before-built-in, matching the
precedence the registry applies when it resolves, so the picker never names
a provider that a compile would not use.

The Playground offers built-ins. They are registered in the same registry as
installed providers and invoked through the same boundary, and a Playground
that could not compile the one language the CLI ships support for would be
useless on a machine with nothing installed.

Whether a frontend's IR versions intersect a target's is a question the view
asks so it can disable an impossible pair and say why. Both version lists
are in the catalog, so the view computes it; the host does not need a
pairing function of its own, because the registry re-checks the pair when it
resolves.

## Invocation

Compile and generate go through `crate::extensions::invoke_frontend` and
`invoke_backend` — the same functions `morphir compile` and `morphir
generate` call. The registry decides the invocation mode: a built-in runs
its typed native handle in process, an installed provider is activated and
driven over MEP. The Playground adds no invocation path of its own, which is
what keeps "the Playground can run it" equal to "the CLI can run it".

One extension instance per invocation, for now. Reusing a negotiated session
across requests needs a session actor in `morphir-daemon`, because
`Session::invoke` consumes the session and returns it inside `InvokeOutcome`,
so a pool built on a mutex and an `Option` has an empty-slot failure mode on
every error path. That actor is a separate change in `ecosystem/morphir-rust`
and the Playground picks it up when it lands; until then a browser pays
extension startup per compile, which is acceptable for a scratch surface and
free for the in-process built-ins.

Every invocation carries a wall-clock timeout. WASM extensions have
`ResourceLimits` covering memory, time, and fuel, but a process-backed
frontend is an ordinary child process with no bound, and a stuck extension
in a Playground means a dead view with no explanation. A lapsed timeout
returns a diagnostic on a well-formed result rather than failing the call.

## Connected protocol

Three methods join `ConnectedMethod` in
`crates/morphir/src/commands/ui/protocol.rs`.

| Method | Params | Result |
| --- | --- | --- |
| `morphir.playground.catalog` | `{}` | `{frontends, targets}` |
| `morphir.playground.compile` | `{languageId, documents, package, irVersion, options}` | `{success, irVersion, ir, diagnostics, modules}` |
| `morphir.playground.generate` | `{ir, irVersion, target, options}` | `{success, artifacts, diagnostics}` |

The compile parameters are `CompileRequest` without `dependencies`, using the
same field names, so the provider builds the protocol request by adding an
empty dependency list rather than translating between shapes. Generate adds
`irVersion` so the provider can resolve a backend without sniffing the IR.

`CONNECTED_PROTOCOL_VERSION` goes to 2. The web assets are built from
finos/morphir-ui and checked in under `ui/assets/`, so the host and the app
ship together and `SessionManifest::validate` rejecting a mismatch is the
behavior we want. No older client is deployed anywhere to strand.

## Session capabilities

A new trait, `PlaygroundCapability`, sits beside `WorkspaceCapability` rather
than extending it. The two have different lifetimes: a workspace provider
binds to a directory when the host binds, and the playground provider holds
no filesystem state at all.

`BoundUiHost::bind` currently takes one workspace provider and always builds
a manifest containing it. It takes a record instead:

```rust
#[derive(Default)]
pub struct SessionCapabilities {
    pub workspace: Option<Arc<dyn WorkspaceCapability>>,
    pub playground: Option<Arc<dyn PlaygroundCapability>>,
    pub initial_view: Option<InitialView>,
}
```

Adding a capability later is one field and no call site changes, and each
call site names what it provides instead of passing a positional `None`. Two
behaviors follow from the record. Manifest construction folds over the
capabilities present rather than assembling a vector by hand, and a request
for a capability that is absent returns a structured error saying so. The
host assumes a workspace provider always exists today, so there is no way to
give that answer at all.

The playground provider gets its own `ProviderManifest` entry advertising the
three methods, alongside the workspace provider's entry.

A request for an absent capability answers with JSON-RPC code `-32013`,
the value the extension protocol uses for the same condition. A request that
reached a provider and failed there answers with `-32603`, so the view can
tell a crashed extension from a control it should disable without matching
on message text. `-32602` stays reserved for a request rejected before any
provider ran.

## Command surface

`morphir playground [--no-open]` reuses `BoundUiHost` unchanged: the same
loopback binding, the same launch token exchange, the same embedded assets.
It passes no workspace capability and a launch URL that routes to the
Playground view.

`morphir ui` passes both capabilities and lists the Playground in its
navigation. When the workspace capability is absent, the manifest says so and
the app disables workspace navigation, which is the mechanism the shell
already uses for optional capabilities.

Landing on the Playground rather than the workspace is a routing question,
and the app has no routing today: its shell route is held in memory and
nothing reads the URL. So morphir-ui gains a hash router, and every view
becomes addressable. `morphir playground` then needs no special protocol at
all: the loopback host redirects the launch-token exchange to `#/playground`
and the router does the rest. Hash routing rather than paths, because the
CLI serves the app's assets directly and a path route would need a
single-page fallback there and equivalent rewrite rules on whatever static
host later serves the same build. A shareable link to a view falls out of
this rather than being designed for.

## Pipeline service

`packages/morphir-workspace/src/connected.ts` gains the three method names
alongside the existing `CONNECTED_METHODS` map, plus Effect Schemas for the
catalog and the two results. That module is the TypeScript mirror of the Rust
protocol types, and every response decodes through `Schema.decodeUnknownSync`,
so a host and app that disagree fail at the boundary instead of somewhere
downstream.

`@morphir/ui` gains a `PipelineService` tag with `catalog`, `compile`, and
`generate`, each returning an `Effect` that fails with `WorkbenchError`. The
connected implementation wraps `ConnectedRpcClient.call`. No new transport
code is needed.

`AppServices.capabilities` gains a `pipeline` flag so the shell can disable
the Playground entry when no pipeline provider is present, matching how it
handles the GitHub capability. `WorkbenchError` already carries an
`unsupported-capability` code, which is what the absent capability path
returns.

## Playground view

`views/playground/PlaygroundView.svelte` lays out three regions using the
existing `RegionPanel` and `ResizeHandle`: a source editor with a frontend
picker, results as Insight, XRay, and IR JSON tabs, and a target picker with
an artifacts pane. `InsightView` and `XRayView` are reused unmodified, fed
through `decodeMorphirIr` and `toWorkspaceIr` from `@morphir/ir`, which is
the path the connected workspace provider already uses. State lives in
`playground-state.svelte.ts` following the existing runes pattern.

The frontend picker lists each frontend with its providing extension.
Selecting one disables targets whose IR versions do not intersect, showing
the reason rather than hiding the option.

Compiling is an explicit action. try-morphir recompiled on every keystroke
because it compiled in process and returned immediately. Here a compile may
start a process backed extension. Debounced automatic compilation becomes
reasonable once the session actor is in place and its effect on latency is
measured.

The editor holds a list of documents from the start, matching
`CompileRequest.documents`, and the first version shows a single tab.
Adding tabs later is view work with no protocol change.

Documents and selections persist through the existing `ConfigService`, so a
reload does not lose work.

## Code editor component

`packages/morphir-ui/src/components/editor/CodeEditor.svelte` is the only
module permitted to import an editor library. It takes a bindable `value`, a
`languageId`, an optional `readOnly` flag, a list of diagnostics, and a
change handler.

The first implementation uses CodeMirror 6. Monaco or another editor can
replace it, and three rules keep that a contained change.

`languageId` is the catalog's language id, not an editor mode name. A
`language-modes.ts` registry maps catalog ids to editor extensions.
`PlaygroundView` passes through what the catalog gave it and never learns how
the editor names its modes.

Diagnostics keep the protocol's shape. `SourceLocation` is a URI and a zero
based start and end position, which is the same shape LSP uses, and both
CodeMirror and Monaco map from it directly. No editor specific diagnostic
type appears in any signature.

An ESLint `no-restricted-imports` rule bans editor library imports outside
`components/editor/`. Without it the boundary decays the first time someone
needs one editor specific feature.

The component ships in `packages/morphir-ui` rather than under the playground
view, because the IR explorer and any future source diff view want it too.

## Errors and diagnostics

Compilation problems are data, not failures. The protocol returns
`CompileResult {success, diagnostics}` rather than failing the call, so a
compile that finds twelve type errors is a successful request carrying twelve
diagnostics. The view renders them as a list and as inline editor markers.

That leaves four failure classes, and the view distinguishes them.

| Class | Origin | Presentation |
| --- | --- | --- |
| Source diagnostics | `CompileResult.diagnostics` | Inline markers and a list, not an error state |
| Capability absent | Missing `SessionCapabilities` field | `unsupported-capability`; the control is disabled with the reason |
| Extension failed | A provider failure or a lapsed timeout | A banner naming the provider; selections are kept |
| Host disconnected | Socket close | The existing `provider-disconnected` path and reconnect |

The third class is why nothing is cached across a failure. A crashed
extension leaves nothing behind, and the next compile starts a replacement,
so the user sees a banner rather than a view that no longer responds.

## Testing

Tests come before implementation, following the repository standard.

The provider is tested against registries it is handed, using extension
doubles registered through the same `NativeExtension` path the built-in
Gleam provider uses, so a test exercises real resolution rather than a
parallel one. Coverage includes an unknown target and an incompatible IR
version answered without reaching an extension, a compile that returns
diagnostics rather than failing the call, and a timeout that returns a
diagnostic.

The protocol gets serde round trip tests per method, mirrored by Effect
Schema decode tests over the same JSON fixtures. Sharing the fixtures is what
catches drift. Two suites asserting their own separate beliefs would not.

The no-write promise, the one most likely to regress without anyone
noticing, is held by censusing three directories across a real invocation:
the directory extensions are started in, the process working directory, and
the Morphir home. One of those tests drives the built-in Gleam frontend and
backend, which write a parse-stage tree unless told not to, so the guard is
watching an invocation that would fail it.

The view is tested against a fake `PipelineService` layer, and `CodeEditor`
is tested against its own contract rather than through CodeMirror, so a
future replacement has a specification to satisfy.

End to end, `morphir playground --no-open` is driven through the launch token
exchange to compile a sample and generate a target, asserting the artifacts
come back in the response.

## Delivery sequence

`ecosystem/morphir-rust` carries the `FrontendRecord` in
`morphir-distribution`, which lands there first because the catalog cannot
report an installed frontend's languages without it. The session actor is a
later, independent change; nothing here waits on it.

Development does not have to wait on a pin. `crates/morphir/Cargo.toml`
declares the morphir-rust crates as path dependencies into the submodule, so
a change in `morphir-daemon` is visible to the CLI build immediately and both
sides can be written in one worktree. Sequencing applies to merging: the
morphir-rust pull request merges, the pin here advances, then the CLI change
merges against the advanced pin.

The protocol methods, `SessionCapabilities`, and the playground provider
follow. The finos/morphir-ui work is gated only by the protocol shape, so
the schemas and pipeline service can start as soon as the method definitions
are settled.

## What this design excludes

try-morphir also evaluates functions through a value editor and steps through
type inference. Neither is in scope here. Evaluation needs an evaluator
reachable from the view, and `@morphir/insight` is a static IR to view
transform today. Type inference stepping is built on morphir-elm's
`Morphir.Type.Infer` and has no equivalent for other frontends, so it fits
poorly beside a frontend picker.

## Future work: browser execution

The `PipelineService` tag is the seam that lets the Playground run without a
CLI. A browser implementation of the same three operations, executing WASM
extensions in the page, makes the Playground work as a hosted static page and
closes the gap ADR-0004 recorded. finos/morphir-ui already reserves the
provider id `browser-local` for this case, and the extension architecture
already separates direct in-process execution from actor hosted execution for
exactly this reason. The Playground view depends only on the tag, so this
becomes a layer swap rather than a rewrite.

Only browser capable extensions can be offered in that mode. Process backed
providers stay available in the connected mode.

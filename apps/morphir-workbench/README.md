# Morphir Workbench

A shared MoonBit/Rabbita frontend for Model Explorer and Try Morphir. It runs as
a standalone browser app and inside the [Proton desktop host](../morphir-workbench-desktop/README.md).
The browser adapter can also use Morphir's existing connected protocol v1 when
these assets are served by an authenticated Morphir host on the same origin.

## Run locally

The [MCK adapter](mck/README.md) exposes the same typed JSON/Ion execution codec
to parent-owned compatibility fixtures. Exact MCK draft.3 adds public-entry
manifest and invocation admission for JSON/Ion text. Draft.1 decoding and draft.2
declared-value admission remain supported. This is an offline
compatibility boundary; connected protocol v1 remains unchanged. Its opt-in `mise run test:workbench-mck`
gate takes an explicit Rust runner and offline corpus; it adds no connected RPCs.

From the repository root, with the pinned mise toolchain installed:

```sh
mise exec -- npm ci --prefix apps/morphir-workbench
mise run build:workbench
mise exec -- npm run dev --prefix apps/morphir-workbench
```

Open `http://127.0.0.1:5173`. Compile & inspect lowers the functional Scheme
subset into real Morphir IR. Compile & run evaluates that IR through the Scheme
backend. Worksheet evaluates each Scheme expression in a fresh session shared
within one run. These are dynamic Scheme values, without type inference or
Scala/JVM dependency resolution. Definitions do not survive a later run.

Choose **Elm** in the Target dropdown, or click **Elm constant**, to generate
an Elm package from the compiled IR using the pure `morphir-elm` backend.
The **Generated** tab shows a folder/file navigator for each module, `elm.json`
and `morphir.json`. The reusable `browser/generated` component puts a selected-file
breadcrumb beside the read-only highlighted preview. Folders and the file list
can collapse independently; keyboard Tab/Enter works for their controls. The
corner expansion icon gives generated output the full editor width while keeping
the source editor and draft mounted. Restore split view returns to source/output
editing. On narrow screens the file list stacks above the preview. The file-header
download icon preserves the selected content;
**Download project** exports a ZIP with every generated file and its relative path.
Archive paths are validated before export. Binary artifacts from connected hosts
remain opaque until the protocol defines their encoding.

Scheme and the bounded MoonBit Boolean frontend are available as local input
languages. With Scheme input, **Compile & run (Scheme)** generates Elm and
evaluates the IR through the existing Scheme runtime. It does not execute
the generated Elm. Generation uses the backend's default model profile and refusal
policy. Refusal codes and IR node locations remain visible while the compiled
model stays available for inspection. Scheme has no type inference, so generation
alone does not guarantee that Elm's compiler will accept every Scheme model.
The example uses `(define answer 42)` with **Compile** to generate a library
without an application entry point. Elm reserves `main` for Html, Svg or Program
values, so Scheme's implicit numeric `main` must be renamed before Elm compilation.

Choose **MoonBit** in Language, or click **MoonBit Boolean**.
The `moonbit-model-bool-v1` profile accepts one function with explicit `Bool`
parameters and return type. Boolean literals, operators and `if`/`else` are
supported; other types, calls, loops and bindings produce profile diagnostics.
Use **Compile**, then select a public function in **Model Explorer** to enter
Boolean inputs and evaluate through typed admission. **Evaluate in Explorer**
is disabled in the compile toolbar because the frontend does not create an
implicit Scheme `main` entry, so **Compile** becomes the toolbar's primary
action. Private functions remain inspectable.

The **Source profile** selector uses the local provider's capability descriptions.
**Single Boolean function** remains the default. Choose **Boolean library**, or
click **MoonBit library**, for multiple explicitly typed Boolean functions,
direct same-file acyclic calls, immutable bindings and lexical shadowing.
Expandable profile details list supported and excluded constructs. Recursion,
cross-file calls, mutation and other source types produce profile diagnostics.
Explorer shows every declaration with its source spelling while retaining the
canonical IR identity. Select any public function to evaluate with fields, JSON
or Ion; zero-input functions require no arguments. Private helpers remain
inspectable and are unavailable as entry points in both local runtimes.
There is no inferred library entry point.

Language and source-profile switches restore each draft and CodeMirror undo history.
Profile selection uses the portable worker's provider descriptors and compiler
callbacks. Connected protocol v1 retains its existing catalog and parameters;
this selector is available locally until a host negotiates profile support.
The Scheme worksheet has its own draft and runtime. It remains Scheme even
when the compile view has MoonBit selected. Elm is a generation target only.

The **MoonBit** Target produces `library.mbt`, `moon.mod`, `moon.pkg` and binary
`symbols.10n`. Text files have read-only highlighting; binary metadata stays
opaque in the preview but file/ZIP downloads retain its exact bytes. The local
worker explicitly declares base64 encoding; connected v1 binary artifacts remain
opaque and unavailable for download until the host protocol defines an encoding.
Generated projects require the pinned `finos/morphir-sdk` dependency and do not
run generated code in the browser. **Download source unit** exports the rich Ion
source unit with original metadata, annotations and provenance. Semantic JSON
export remains separate and does not carry that metadata.

The global navigation retains its collapse choice per experience. Model Explorer
shows the model tree in its contextual sidebar; Try Morphir shows examples, and
its page heading describes the active layout. Source, results and the selected declaration survive navigation.
The top bar's rounded arrow button, with a **Back** tooltip, retraces experience, worksheet and declaration
navigation, including references and Used by links. It restores the search and
detail view recorded at that destination and works with the sidebar collapsed.
Editing source does not add history entries or undo source changes. Selecting a
different function resets its evaluation inputs and result. History keeps the
latest 100 destinations in memory; replacing a model clears declaration and
search destinations while retaining experience navigation. Back is disabled
when no earlier destination is available.
Imported JSON versions 1–4 are decoded and migrated explicitly to the current
semantic model. Local export writes normalized v4 JSON. Source and model state
are held in memory, so reloading starts a fresh session.

## Model Explorer

Import `pkgs/morphir-ir/conformance/fixtures/v3-greeting.json` for an example with
records, custom types, documentation and functions. The overview shows the loaded
package and distribution kind, the normalized current IR version and declaration
counts. Each module can collapse independently. Search temporarily reveals matching
modules and declarations without replacing those collapse choices.

Select Product to inspect its record fields and documentation, then follow
Main.ProductId. References inside the loaded model navigate to their declaration;
constructor references navigate to the owning custom type. References outside the
model's own declarations show their qualified identity without a navigation button.
Used by lists declarations that reference the selected type or value.

Value details show ordered parameters, the result type and whether the definition
is portable, native, external, incomplete or specification-only. Type details show
aliases, record fields, constructors and opaque specifications. Signatures are a
readable projection of decoded current IR, not recovered source. IR JSON retains
access to each normalized declaration and the complete distribution.
Portable definitions can run directly from Explorer. Select `applyDiscount` in the
greeting fixture, set **discountPercent** to `20` and **originalPrice** to `100`,
then choose **Evaluate**: the local runtime returns `80.0`. **JSON inputs** accepts
`[20, 100]` in the same declared order.

The reusable `browser/evaluation` component generates labeled fields from the
same semantic schema as the input validator. Text fields cover Float/Int/Char,
multiline text controls cover String, Boolean and constructor selectors offer
valid choices, and nested groups cover records, tuples and lists. Lists support
adding/removing items; choosing a constructor initializes its ordered arguments.
The CodeMirror wrapper remains available through **JSON inputs**. Both modes edit
one document and retain values and exact numeric spelling when switching.

`arguments` applies nested edits to the latest document and preserves partial
numeric text until it becomes a valid number. Runtime validation rejects an
unfinished number. Invalid JSON or incompatible shapes remain intact when
switching to fields; **Reset inputs** explicitly restores defaults. Inputs that
would render more than 200 nodes use the JSON editor to keep the UI manageable. `evaluation.mbt` resolves generic aliases and validates Bool,
Int, Float, String, Char, Unit, records, tuples, lists and public custom constructors.
Integers must be decimal strings, such as `"9007199254740993"`, to preserve exact
values. Record keys use canonical Morphir names (`order-id`); custom values use
`{"constructor":"elm-compat:main#pending","arguments":[]}`. Generated defaults and
input descriptions show the accepted shapes. Input text is data, never Scheme code.

Each evaluation uses a fresh worker and the existing Scheme backend. The reusable
`browser/result` component shows a collapsible tree of records, lists, tuples and
constructors projected directly from runtime values. Integers and rational numbers
remain exact text; Float results also retain their IEEE 754 bits. Canonical
constructor tags and improper-list tails stay explicit. **Result JSON** and
**Printed** reuse the read-only CodeMirror component. The printed view keeps the
runtime's original value format, such as `#t` for true.

The display projection visits at most 500 values, with depth 32 and a 16,384-character
scalar display limit. Omitted children or text have visible truncation markers;
procedures and embedded IR values have opaque labels. JSON shows this bounded
display tree, not the upstream invocation-value codec or a round-trip value export.
The full printed view remains available in Local Scheme mode.

**Typed invocation** uses the merged `morphir-invocations-v1` codec and the
`morphir-engine/execution` bounded Scheme evaluator. It is available for public
entries admitted by the MoonBit generator's manifest. **Input and output types**
shows the manifest and custom constructor registry. Generator rejection leaves
local inspection and Scheme evaluation available with an explanation in typed mode.
This mode evaluates through the shared interpreter; generated-code execution and
connected evaluation remain separate work.

Import `apps/morphir-workbench/fixtures/typed-pricing.json`, select `Quotes.total`,
and choose **Typed invocation**. Set **quote.price.coefficient** to `125`,
**quote.price.exponent** to `-1` and **quote.quantity** to `3`, then evaluate.
The fixture is exported from the merged
`morphir-moonbit/fixtures.pricing()` model. The same arguments in **JSON inputs** are:

```json
[{"type":"record","fields":[
  {"name":"price","value":{"type":"decimal","coefficient":"125","exponent":-1}},
  {"name":"quantity","value":{"type":"int","value":"3"}}
]}]
```

The result is `{"type":"decimal","coefficient":"375","exponent":-1}`.
Tagged arguments are ordered by parameter and validated by the shared profile
before evaluation. Int values and Decimal coefficients are decimal strings;
Float64 uses its unsigned 64-bit `bits` string; Text and Character carry UTF-16
`units` arrays, including isolated surrogates. Maybe, Result, lists, tuples,
records and custom constructors use the published codec shapes. The profile's
1-MiB encoded invocation limit and value budgets apply.

**Result JSON** returns the complete canonical typed value in this mode. **Value**
uses a separately bounded presentation tree; **Printed** shows canonical JSON text.
Model/domain errors have the `model-error` tag and remain successful evaluations,
separate from `Result.Err` values and validation/runtime failures. Switching runtime
modes cancels the active request, clears the result and resets the argument document.
The reusable `browser/typed-input` component edits the canonical argument document
directly. Int and Decimal controls preserve string coefficients. Float64 provides
finite-number and exact-bit controls; editing the bits leaves NaN payloads intact.
Text and Character have Unicode controls when the units are representable, plus
expandable UTF-16 unit controls for isolated surrogates and unfinished edits.
Records preserve their field order; tuple/list groups, Maybe/Result cases and custom
constructor choices initialize values using the shared default generator.

Fields and **JSON inputs** retain the same document. Numeric drafts remain visible;
execution validation rejects them until completed. Unexpected tags, record fields,
constructor owners or invalid JSON fall back to a repair message without replacing
data. Forms visit at most 200 values/units with depth 32. Recursive types are
rendered from their actual finite values; additions that have no bounded finite
default use JSON input. Upstream connected profile publication remains pending.

**Ion inputs** accepts one Ion list in parameter order through the same editor
component. Typed mode uses the published `Value::from_ion` codec. Int, Bool and
Decimal are native Ion values; Unit uses `morphir_unit::null`; rich values use
`morphir_value` annotations. For example, `Boundaries.decimal` accepts `[12.50]`
and returns the canonical Decimal coefficient `125`, exponent `-1`. `Quotes.total`
accepts:

```ion
[morphir_value::{type:"record",fields:[
  {name:"price",value:{type:"decimal",coefficient:"125",exponent:-1}},
  {name:"quantity",value:{type:"int",value:"3"}}
]}]
```

Switching between Ion and fields/JSON converts the representation through the
codec and keeps exact values. A malformed draft or unsupported conversion stays
in its original tab with a diagnostic. Evaluation parses Ion in the worker and
then applies the same invocation/type validation and result handling. Ion syntax
highlighting is lexical; it does not validate the value profile.

Local Scheme mode accepts a restricted Ion projection into its existing input
shapes. Native Int values become exact decimal strings for declared Int inputs;
finite numbers, strings, booleans, untyped nulls, lists and structs are supported.
Decimal-to-Float conversion follows the declared local binary64 semantics.
Duplicate fields, annotations, symbols, timestamps, typed nulls and binary values
are rejected rather than silently discarded or coerced. Use Typed invocation for
the published Morphir value profile. Neither mode executes Ion as source code.

Editing arguments marks the
previous result as outdated. A reply for another function or replaced model cannot
replace the current result, and Cancel terminates the worker. Results are separate
from compile and worksheet output.

Specifications, native/external/incomplete definitions, private constructors,
unresolved type variables and unavailable input types show an
unavailable explanation. Supported input shapes do not guarantee that every
referenced SDK operation has a runtime binding; execution errors appear in the
result panel. Connected protocol v1 has no evaluation method, so this component
shows its availability message in that mode without sending an RPC extension.

The portable `inspector.mbt` builds this projection from semantic IR. Its selection
keys include declaration kind because a type and value can share a qualified name.
`browser/model-explorer` owns the UI component; it does not decode legacy wire shapes
or introduce RPC methods. Both standalone and connected models use the projection.
Search, selected declaration and module collapse state survive experience navigation.
Loading a replacement model clears search, selection and module collapse choices.

## Tool panel

A bottom tool panel in both experiences hosts **Logs**, **Diagnostics** and
**Output**, as in an IDE. It starts collapsed as a compact bar with the tabs,
the current operation status and an icon to open it. Select a tab to open it;
select the open tab again, or use the collapse icon, to close it. Maximize
makes the panel taller and Restore returns it to its normal height. The open
tab and size are kept when you move between Try Morphir and Model Explorer.
The tabs follow the ARIA tabs pattern: Arrow keys, Home and End move focus and
selection without scrolling the page.

The workbench is one window tall. The workspace above the panel scrolls on its
own, so an open panel takes its height from the code panes and never covers
focusable controls. Code panes keep a smaller 180 px minimum while the panel is
open.

The panel shows only what the application did and what hosts returned. It
does not capture the browser console or add host capabilities.

- **Logs** keep the last 200 application operations: initialize, compile, run,
  worksheet, import, project open, evaluation, downloads, export, cancellation,
  runtime changes and ignored late replies. Each entry has its job, the
  revision it read and its duration.
- **Diagnostics** keep the last 20 reports, up to 50 diagnostics each. A report
  belongs to its operation and to the revision of the source, worksheet, inputs
  or model it read. It is **Current** only while it is the newest report for
  that scope and the revision has not changed. Editing the source, or replacing
  the model, makes older reports **Previous**. The problem count includes
  current errors and warnings only. MoonBit frontend diagnostics keep their code
  and show an editor position; the original coordinates
  (`moonbit-parser-position-v1`, one-based lines, zero-based columns) appear in
  the tooltip. Frontend and backend naming warnings retain their stage, code,
  related declaration owners, authored and allocated spellings, and suggested
  fix. A compact disclosure shows the details. A warning counts once even when
  it has several related declarations; at most 20 related locations are retained.
  Generator refusals keep their IR node path. When a connected v1
  compile fails, the panel keeps the host's diagnostic severity, code and
  zero-based range; this adds no RPC method or field.
- **Output** keeps the last 50 outcomes: run values, worksheet expressions and
  values, evaluation results and failures, and compile or import summaries.
  Generated files and IR stay in their panes.

All host text renders as text, and messages longer than 4,000 characters are
truncated. Each tab has a Clear action. The `browser/bottom-panel` component
owns the typed state, the actions, the reply parsing and the view.

## Visual identity

The workbench follows [Morphir's site](https://morphir.finos.org/): blue
`#00a3e2`, orange `#ff6a00`, white panels and neutral gray surfaces. Links,
selected labels and focus outlines use the site's darker blue `#00729e`.
Primary actions pair orange with dark `#1c1e21` text.

Each screen has one primary action. Try Morphir promotes the run action when
the layout can run and **Compile** otherwise; Cancel appears only while a job
runs. Secondary actions, such as source-unit, project and IR downloads, use
quiet icon buttons. Input and result views are tabs, and the evaluation runtime
is the only segmented switch inside an evaluation card. Profile details and
input and output types stay behind disclosures until needed. Stale and failed results keep an orange or red accent and label.
Try Morphir's source and output panes fill the window height between the
controls and the tool panel and scroll inside their editors, with a 320 px
minimum for short windows. The generated-file list takes only its content
width, up to 200 px, so code gets the rest of the output pane. On
screens up to 650 px wide, the sidebar becomes a band above the page with
icon-only navigation, so the content keeps the full width.

The original Morphir vector logo and a cropped compact mark ship in `assets/`.
The cube, code and sidebar navigation icons are workbench drawings. Assets load
locally in both browser and Proton builds; no icon font or CDN is required.
See [asset provenance](assets/README.md) for sources and modifications.

## Editor component

[CodeMirror 6](https://codemirror.net/) powers the reusable
`browser/editor` component. Its typed MoonBit `Props` provide document identity,
text, language, label and read-only mode; `view` accepts an optional change
emitter. `code-editor.js` owns the editor inside a custom element's shadow root,
mounts it on connection, applies controlled updates and destroys it on removal.
No DOM observer or page-wide editor patching is used.

The source editor has line numbers, selection, bracket matching, folding,
search and undo/redo. A bounded in-memory document cache retains cursor and undo
history across navigation and keeps compile and worksheet documents separate.
External text replacements start a new history. Typing emits one source update;
controlled updates do not echo another edit. Tab keeps normal focus navigation.

Scheme, MoonBit, JSON, Ion, Scala, Elm, JavaScript, TypeScript, Java and Python have syntax
highlighting. The host's language and target IDs select the mode; unknown IDs
use plain text. Morphir IR, model details and generated output reuse the same
component in read-only mode. Highlighting does not provide compiler diagnostics,
type checking or language-server completion.

All editor code and grammars are bundled locally into `dist/code-editor.js`.
The ZIP export helper and pinned `fflate` dependency are bundled into
`dist/artifact-download.js`.
The browser and Proton package use that same bundle without a CDN or extra worker.

## Runtime boundaries

`browser/main.mbt` owns rendering and application state. `pipeline.mbt` calls the
existing Morphir Scheme frontend, IR codecs/migrations and Scheme backend.
Elm generation also runs in that worker through the pure Elm backend.
`worker/main.mbt` hosts that portable pipeline in a dedicated worker. Each job
gets a fresh worker; cancel terminates it. The adapter imposes a 15-second wall
clock deadline and separate 16-MiB source/argument text limits in addition to the runtime's evaluation
limits. These limits are not a complete memory sandbox.

`browser/transport.js` owns browser APIs and connected JSON-RPC. No native
filesystem or process APIs are imported by the UI. The desktop host packages
the same frontend and worker without a second implementation of either view.
The initial desktop runtime uses the worker; a native engine bridge is future work.

## Connected host compatibility

Use `?mode=connected` only when the assets are served by the Morphir host that
provides `/api/session` and `/rpc`. Authenticate through that host's `/launch`
flow first. The development server can keep the frontend and authenticated host on one
browser origin through an explicit loopback proxy:

```sh
MORPHIR_WORKBENCH_HOST_URL=http://127.0.0.1:HOST_PORT mise exec -- npm run dev --prefix apps/morphir-workbench
```

Start the upstream Morphir UI/playground host first. Open its one-time launch URL
with the origin changed to the workbench server's origin, keeping `/launch` and
the token query. The proxy exchanges the token with the upstream host, retains
its HttpOnly session cookie, then redirects to this frontend in connected mode.
It forwards only `/launch`, `/api/session` and `/rpc`; ordinary assets are local.
The upstream target must be an explicit `http://127.0.0.1:<port>` origin. The
proxy binds to loopback, checks its own Host/Origin and cross-site request headers,
and rewrites Host/Origin only after those checks. Tokens and cookies are not logged.

The upstream Rust host currently embeds its own frontend. Serving these assets
there directly is another integration option. This client never sends an
arbitrary cross-origin browser request to a daemon.

The adapter validates protocol version 1, initializes the advertised session,
loads the playground catalog and available workspace projects, and uses:

- `morphir.session.initialize`
- `morphir.playground.catalog`, `.compile`, `.generate`
- `morphir.workspace.open`
- `morphir.project-model.open`

Capability names retain upstream slash spelling (`morphir/playground/compile`)
and wire methods retain dotted spelling. Source references are provider/locator
identities; the client does not invent filesystem paths. Compiler and generation
targets come from the host catalog. Compile requests omit `exposedModules`,
which means expose all, and never name a provider directly.

The wire shapes follow [finos/morphir protocol.rs](https://github.com/finos/morphir/blob/5c5307d89f34d876e8f1ebf561ec55efbadf9fa0/crates/morphir/src/commands/ui/protocol.rs).
No new wire method or protocol version is introduced by this slice. v1 does not
offer evaluation or server cancellation. Those controls are unavailable when
connected; Discard ignores a reply while the host may keep running. Workspace
watching, reconnect/replay and native daemon attachment are not implemented yet.

The candidate workbench profile remains a design proposal in
`.dev/design/morphir-workbench.html`. Evaluation, job and artifact extensions
must be contributed with schemas and compatibility fixtures to finos/morphir
before this application can advertise them. No such profile has been published.

## Verification

```sh
mise run setup:workbench
mise run test:workbench
```

The focused checks cover real compile/run, worksheet session isolation, malformed
source, worker cancellation, JSON-RPC correlation and capability negotiation,
strict v1 parameter shapes, model import/export, retained navigation context and
mobile overflow. Elm checks cover target selection, source/manifest highlighting,
exact file/ZIP downloads and retained IR after generation refusal. Packaged Proton
acceptance checks the same viewer and emitted download bytes at its application
origin without an OS save dialog. Generated-file acceptance also exercises multiple
modules with identical basenames, manifests, Unicode/deep paths, empty and binary
files, folder/list collapse, keyboard selection and source retention in the focus
layout. The default connected checks use fixtures. Opt-in acceptance starts a real Rust
`morphir ui` host in a temporary workspace and private Morphir Home, exchanges
its single-use launch token through the proxy, then negotiates a session and
catalog. It compiles Gleam, generates an artifact and opens that model through
workspace/project-model RPC and Explorer. No provider installation is needed
for the built-in Gleam provider. The test cleans up its processes and fixtures.

Build the Rust binary from a compatible finos/morphir checkout, then run from
this repository root:

```sh
mise run test:workbench-live-host -- --host-bin /absolute/path/to/morphir
```

The portable MoonBit launcher uses core `argparse` and the normal MoonBit script
runtime. Browser assertions live in the existing Playwright workflow. This test
is optional and does not make Rust a dependency of the standalone app or its
regular test suite. A missing binary fails the test.

Live acceptance passed with finos/morphir `5c5307d89f34d876e8f1ebf561ec55efbadf9fa0`, its
pinned morphir-rust submodule `04ababf1dbeff10333bdaa70613562157843125a`,
Rust 1.98.1 and Chromium. The v1 `morphir.workspace.open` result wraps the workspace
in `snapshot`; malformed envelopes now report a diagnostic while keeping compiler
capabilities available. Other installed providers, connected evaluation,
workspace watching and durable daemon recovery need their own acceptance.

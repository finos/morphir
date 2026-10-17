# Morphir Workbench

A shared MoonBit/Rabbita frontend for Model Explorer and Try Morphir. It runs as
a standalone browser app and inside the [Proton desktop host](../morphir-workbench-desktop/README.md).
The browser adapter can also use Morphir's existing connected protocol v1 when
these assets are served by an authenticated Morphir host on the same origin.
Packaged Proton also negotiates a page-bound desktop session. It
uses browser workers for compilation and explicitly selected Local Scheme evaluation.
On qualified macOS Apple Silicon packages, Typed invocation uses owned native
workers. The explorer also offers read-only workspace grants. Explicit connected launches take precedence over this bootstrap.

`browser/job-session.js` owns shared job observation and receipt validation.
`browser/job-transport.js` carries bounded HTTP text frames; an injected transport
uses the same decoder, cursor, cancellation and release logic. Native desktop
transport supplies raw business frames to that same client after page-bound
session checks. See the desktop README for budgets and platform qualification.

## Runtime capabilities

Capability claims are provider-authored assertions about supported operations,
features and behavior. Capability verification gathers scoped contract and MCK
evidence that an implementation behaves as claimed. It is not formal proof of
correctness for all programs or business outcomes.

Capability validation checks that the chosen runtime/provider meets the
requirements of a particular run, selected function and model revision, before or as execution
proceeds under policy. Unsupported-feature decisions are capability checks.
Model, type, argument, output, receipt and authority checks remain ordinary
validation. Existing protocol identifiers and public offers are unchanged.

## Run locally

The [MCK adapter](mck/README.md) exposes the same typed JSON/Ion execution codec
to parent-owned compatibility fixtures. Exact MCK draft.3 adds public-entry
manifest and invocation validation for JSON/Ion text. Draft.1 decoding and draft.2
declared-value validation remain supported. This is an offline
compatibility boundary; connected protocol v1 remains unchanged. Its opt-in `mise run test:workbench-mck`
gate takes an explicit Rust runner and offline corpus; it adds no connected RPCs.

From the repository root, with the pinned mise toolchain installed:

```sh
mise run setup:workbench
mise run build:workbench
mise exec -- bun run --cwd apps/morphir-workbench dev
```

Open `http://127.0.0.1:5173`. Compile & inspect lowers the functional Scheme
subset into real Morphir IR. Compile & run evaluates that IR through the Scheme
backend. Worksheet evaluates each Scheme expression in a fresh session shared
within one run. These are dynamic Scheme values, without type inference or
Scala/JVM dependency resolution. Definitions do not survive a later run.

The local worker compiles through `@engine.Engine` with the MoonBit and Elm providers: discover, plan and
`execute_content`. Generation uses the engine backends `scheme`, `elm` and `moonbit`. A request carries `source`
(one file) or `project` (`name`, `languageId`, `files[]`, optional `frontendProvider`, `frontendProfile`,
`exposedModules`).

Choose **Elm** in the Target dropdown, or open the **Elm constant** sample, to generate
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

Choose **MoonBit** in Language, or open the **MoonBit Boolean** sample.
The `moonbit-model-bool-v1` profile accepts one function with explicit `Bool`
parameters and return type. Boolean literals, operators and `if`/`else` are
supported; other types, calls, loops and bindings produce profile diagnostics.
Use **Compile**, then select a public function in **Model Explorer** to enter
Boolean inputs and evaluate through typed validation. **Evaluate in Explorer**
is disabled in the compile toolbar because the frontend does not create an
implicit Scheme `main` entry, so **Compile** becomes the toolbar's primary
action. Private functions remain inspectable.

The **Source profile** selector uses the local provider's capability descriptions.
Fresh local MoonBit projects select **Supported MoonBit library 2026-10-17**,
`moonbit-model-library-2026-10-17`, which combines every currently qualified source
capability. Open **MoonBit library** for an example using Bool, String and Int32
in one file. The documented sample includes:

- `greet` and `welcome` for concatenation, typed lets, helpers and conditional text.
- `precedes`, `compare_names` and `in_name_range` for all four shortlex ordering
  operators. `precedes("b", "aa")` returns true.
- `should_welcome` for nonempty text, Boolean conjunction and negation.
- `choose_for` and `choose_earlier` for String logic selecting exact Int32 values,
  including the Int alias, constraints, equality and disjunction.
- `unicode_sample` for supplementary and combining escapes, preserved exactly.

Function documentation transfers to IR and generated MoonBit/Scheme comments.
String inputs retain their UTF-16 and size guards on every public function,
including those that return Int32. New cumulative snapshots use their qualification
date, with a revision suffix for same-day iterations.

This is local source conformance for a finite subset. Numeric literals, arithmetic
and comparisons, String indexing/methods, imports and installed ecosystem
qualification remain outside this version. Profile details list those exclusions.
The earlier v1 and v2 profiles remain selectable with their existing contracts.
Explicit saved choices stay pinned. **MoonBit Boolean** and **MoonBit Boolean library** open their corresponding
legacy profiles. **MoonBit String library** opens the greeting example in the
cumulative profile, so users can add any other qualified scalar capability.

Explorer shows each declaration with its source spelling and canonical IR identity.
Select a public function to evaluate with fields, JSON or Ion; zero-input functions
require no arguments. Private helpers remain inspectable and are unavailable as
entry points. The frontend does not infer a library entry point.

Language and source-profile switches restore each draft and CodeMirror undo history.
Profile selection uses the portable worker's provider descriptors and compiler
callbacks. Connected protocol v1 retains its existing catalog and parameters;
this selector is available locally until a host negotiates profile support.
The Scheme worksheet has its own draft and runtime. It remains Scheme even
when the compile view has MoonBit selected. Elm is a generation target only.

The **MoonBit** Target produces `library.mbt`, `moon.mod`, `moon.pkg` and binary
`symbols.10n`. Text files have read-only highlighting; file/ZIP downloads retain the exact bytes of binary files.
A generated file has a context menu (right-click, Shift+F10 or its ⋯ button) with Copy path and Download, and for a
binary file **View as Ion text** and **View raw (hex)**. View as Ion text decodes a binary Ion file (one that starts
with `E0 01 00 EA`) to pretty Ion text in the browser-local worker, as a job. Each limit stops the work before it
grows: at most 4 MiB in (checked before base64 decoding), at most 128 levels, 100,000 values (nulls included) and
64 KiB for one integer or decimal (checked by a walk of the binary structure before the Ion reader runs), and at
most 4 Mi characters out (counted while the text is written). The viewer marks the decoded view and has **Show
binary summary** to go back. Decode errors carry their `ion.*` or `workbench.*` code in the tool panel's details.
View raw (hex) shows the first 64 KiB. The command palette offers View as Ion text for the selected file. The local
worker explicitly declares base64 encoding; connected v1 binary artifacts remain
opaque and unavailable for download until the host protocol defines an encoding.
Generated projects require the pinned `finos/morphir-sdk` dependency and do not
run generated code in the browser. **Download source unit** exports the rich Ion
source unit with original metadata, annotations and provenance. Semantic JSON
export remains separate and does not carry that metadata.

The global navigation retains its collapse choice per experience. Model Explorer
shows the model tree in its contextual sidebar; Try Morphir shows the project explorer, and
its page heading describes the active layout. Source, results and the selected declaration survive navigation.
The top bar's rounded arrow button, with a **Back** tooltip, retraces experience, worksheet and declaration
navigation, including references and Used by links. It restores the search and
detail view recorded at that destination and works with the sidebar collapsed.
Editing source does not add history entries or undo source changes. Selecting a
different function resets its local evaluation inputs and result. The latest connected
host evaluation keeps its own draft and full result when navigating away and back.
History keeps the
latest 100 destinations in memory; replacing a model clears declaration and
search destinations while retaining experience navigation. Back is disabled
when no earlier destination is available.
Imported JSON versions 1–4 are decoded and migrated explicitly to the current
semantic model. Local export writes normalized v4 JSON. Source and model state
are held in memory, so reloading starts a fresh session.

Elm is in the Language picker. The single editor holds one Elm module: its header (`module A.B.C exposing (..)`)
gives the package `A.B`, the file `src/A/B/C.elm` and the exposed module `C`. A frontend failure lists its
problems in the bottom panel by file. The panel shows an Elm or Morphir source column as written, and a MoonBit
parser column plus one, following the `coordinateProfile` of each problem
(`elm-source-position-v1`, `moonbit-parser-position-v1`, `morphir-source-location-v1`).

## Size

Moving the worker onto the engine and adding the Elm provider changed `dist/worker.js` from 17,643,040 bytes to
20,113,918 bytes (+2,470,878 bytes, +14.0%). There is no size budget. `execute` builds a fresh engine for each
request.

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
entries listed in the MoonBit generator's manifest. **Input and output types**
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
default use JSON input. Connected hosts use the separate authenticated job profile described below.

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
result panel. Connected protocol v1 has no evaluation method. Without a separately authenticated
job offer, this component shows its availability message without sending an RPC extension.

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
  fix. Each row's **Details** disclosure shows them. A warning counts once even when
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

### Failure details

A failed job and each diagnostic open their details in place, with the keyboard or a screen reader (disclosure
buttons with `aria-expanded`). A diagnostic shows its code, severity, stage, location (select it to open the file at
that place) with the original coordinates, the full message, related declarations and fix, and the job that
reported it. A failed job in Logs or Output shows its code, stage and message with the job's context: language,
profile, provider, target, project and file count, source revision and duration. **Copy details** copies a
plain-text report to paste into an issue; its first line is "Messages can quote your source." **Raw reply** shows
the reply JSON, at most 8,000 characters. It keeps names, numbers, codes, stages, paths, settings and messages;
messages can quote the source line a failure points at.
Source text, models and evaluated values (any shape: `content`, `irSource`, `sourceUnitIon`, `expression`, `ir`
and similar) become `<omitted: N characters>`, a `source` member stays only as a numeric line and column location,
and any other text longer than 32 characters becomes its size. Codes are the replies' own; a codec error in a
request or model is `workbench.invalid_request` or `workbench.invalid_model`, anywhere else
`workbench.internal_error`, and keeps the codec's code and detail.

## Visual identity

The workbench follows [Morphir's site](https://morphir.finos.org/): blue
`#00a3e2`, orange `#ff6a00`, white panels and neutral gray surfaces. Links,
selected labels and focus outlines use the site's darker blue `#00729e`.
Primary actions pair orange with dark `#1c1e21` text.

A page that hosts the workbench can add `<meta name="morphir-site-home" content="<url>">`. The breadcrumb then
starts with a **Morphir** link to that URL, and the logo links there too. The project site does this at `/try/`;
the desktop host and the development server do not.

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
The packaged desktop adds page-bound typed native commands for owned evaluation
workers and read-only workspace grants on qualified macOS Apple Silicon builds.
The explorer's **Open workspace** action uses the OS folder picker, discovers
projects through the shared engine, and opens saved JSON or Ion checkpoints.
**Original file** retains the exact imported bytes and version; **Export IR**
exports the normalized current IR. Rich Ion retains its logical unit identity,
annotations, metadata and provenance. Browser-only runs continue to use file
imports; connected launches use their host's workspace protocol.

## Connected host compatibility

Use `?mode=connected` only when the assets are served by the Morphir host that
provides `/api/session` and `/rpc`. Authenticate through that host's `/launch`
flow first. The development server can keep the frontend and authenticated host on one
browser origin through an explicit loopback proxy:

```sh
MORPHIR_WORKBENCH_HOST_URL=http://127.0.0.1:HOST_PORT mise exec -- bun run --cwd apps/morphir-workbench dev
```

Start the upstream Morphir UI/playground host first. Open its one-time launch URL
with the origin changed to the workbench server's origin, keeping `/launch` and
the token query. The proxy exchanges the token with the upstream host, retains
its HttpOnly session cookie, then redirects to this frontend in connected mode.
It proxies `/launch`, `/api/session` and `/rpc`; ordinary assets are local.
The optional job endpoints described below execute in this gateway.
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
offer evaluation or server cancellation. Without the separate job offer, evaluation controls are unavailable when
connected; Discard ignores a compile reply while the host may keep running.
Workspace watching and native daemon IPC are not implemented yet.

The separate live job profile is contributed to
[finos/morphir](https://github.com/finos/morphir/tree/98f9ad980b2c64a89ce550c6eee45e69834d300f/spec/workbench/host/draft.1).
It preserves connected v1 and the existing job receipt and terminal contracts.

<a id="native-descriptor-admission"></a>

## Native descriptor validation

The shared job client accepts paired `nativeDescriptor()` and
`nativeRequest(source)` hooks. The descriptor hook supplies JSON descriptor text
after the binding checks its current page and session. If it extracts a descriptor
from a public reply, it must validate the complete original reply with bounded,
duplicate-aware decoding before projecting that descriptor. The compiled
`native-descriptor` command uses the shared native reply codec to check the exact
profile, closed capabilities and directly nested frozen jobs offer. Its session
must match the current page session. HTTP retains separate authenticated
host-descriptor validation.

The request hook receives a complete public native job request as JSON text,
including profile, version, operation, session and payload. Preflight bounds the
whole 1-MiB envelope before sending. The hook returns the complete raw native
reply text for compiled `native-response` validation against that originating
operation and session. Initial session-open validation may use a null expected
session; later calls require the known session. The binding must correlate its
own concurrent invocations and enforce deadlines and current-page checks.

Both transports use the existing receipt cursor. Only a closed native error
with `effect:none` proves that this submission caused no new effect; the client
allows a later explicit submit and never retries automatically. Unknown effects,
malformed/lost replies and transport exceptions leave submission uncertain.
Transport exceptions cannot manufacture a validated effect. Native errors carry
no fabricated HTTP status. Terminal release absence can confirm cleanup only
after fresh, matching authority validation and an authoritative no-effect error.

Reconciliation checks the same job authority and stable native capabilities
before observing a retained identity. Missing jobs are explicit absence, and
malformed negotiation never falls back to another transport. The bundled Proton
host and renderer now use this raw mapping through `app:workbench_native` for
all session, job and workspace operations. The session binding validates complete
replies before extracting descriptors and rechecks stable authority after each
request. Independent MCK drafts.7 through .10 cover raw frames, reply validation,
production client lifecycle and controlled production owner orchestration. Fresh
packaged-target lifecycle qualification remains separate before public
conformance advertisement. Controlled context does not establish native caller
authority; the byte-oriented codec supplies the earlier UTF-8 framing boundary.

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

Chromium acceptance includes a real directory upload. CEF cancels CDP directory
enumeration, so the packaged smoke test supplies the fixture's selected `File`
objects and relative paths through the requested folder input. The production
file reader, bounded import and compilation still run. OS folder-dialog selection
and native workspace grants retain their separate acceptance requirements.

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
capabilities available. Other installed providers, workspace watching and durable daemon recovery need
their own acceptance. The opt-in job acceptance below exercises connected evaluation.

## Projects

The editor holds one project for each language. The pure model is the package
`finos/morphir-workbench/project`.

- A project keeps its files under `src/`. Paths are relative and use `/` between folders.
- A language that compiles one file at a time (Scheme, MoonBit) holds one file. "New file" is disabled and
  the reason names `morphir-ukvn.5.22.14`, where projects of several files are planned.
- An Elm project holds many files. A new Elm file starts with its module header.
- An Elm package exposes modules relative to the package name: in package `Shop.Orders`, the file
  `src/Shop/Orders/Api.elm` is module `Api`. Renaming a file moves its exposure; deleting a file drops it.
- A project always keeps at least one file, and the active file always exists.
- A folder is implied by the paths of its files. Renaming a folder moves each of its files under the rules of a file
  rename; deleting a folder deletes its files, and is refused when it holds every file.

### Project explorer

In Try Morphir the project is a tree in the sidebar, as in a code editor (package
`finos/morphir-workbench/browser/project-files`). Folders come from the paths and sort before files, by code unit;
a chain of single folders shares one row (`src/Workbench`). Rows show an icon for the file type, the problems of the
last compile (folders show the sum) and, for Elm, an arrow on exposed modules. The header holds the package name
(select it to rename the package) and New file, Import folder, Collapse folders and More actions.

- Right-click a row, or press Shift+F10 or the menu key, for its menu: Open, New file, Rename, Delete, Copy path,
  Expose module or Stop exposing module, Show problems. More actions holds the project menu, with Reset project.
- New file and Rename edit the name in place; Enter commits, Escape cancels, and a refusal shows under the input.
  A name can hold `/` to make folders. Delete asks in the row; Enter deletes, Escape keeps.
- The tree follows the WAI-ARIA tree pattern: arrows, Home, End, Enter (open and go to the editor), Space (open and
  stay) and a letter to jump. F2 renames and Delete or ⌘⌫ deletes the focused row.

### Shortcuts and the command palette

Mod is ⌘ on macOS and Ctrl elsewhere. Mod+P opens quick open over the project's files; Mod+Shift+P or F1 opens the
command palette (a leading `>` in the same input lists commands); Mod+Enter compiles. These three work in the editor
too; tree shortcuts work only on a focused row. The palette matches letters in order (fuzzy), marks the matched
letters, lists recently run commands first, shows each command's shortcut and dims a command that cannot run now with
its reason. Switch language, Set generation target and Open sample ask a second question in the same palette.
The keymap is one table in `finos/morphir-workbench/browser/keys`; menus and the palette read it, so a shortcut is
shown where it works. Fuzzy matching, filtering and the palette state are in
`finos/morphir-workbench/browser/command-palette`.

## Samples

The Elm samples are static JSON assets under `assets/samples/elm/`: `index.json` (id and title in menu order) and
one file for each sample (`examples-tutorial`, `elm-rentals`, `records`). The build copies them to
`dist/samples/`, and the page fetches a sample when the person picks it. The worker and the shell do not embed them.

Each asset has a `notice` with its origin and licence, taken from `pkgs/morphir-elm/conformance/SOURCES.md`; the
page shows it with the sample. Scheme and MoonBit keep their built-in examples, which are listed from code.

One list feeds both places that open a sample: the command palette has one "Open sample: …" entry for each, and the
explorer's project menu (its ⋯ button, or a right-click on empty explorer space) has a "New from sample" section. The
built-in examples (Pricing & arithmetic, Elm constant, MoonBit Boolean, MoonBit library, MoonBit Boolean library, MoonBit String library) are listed for every
language; the Elm samples follow while Elm is selected. The worksheet lists only its own example.

The assets come from the Elm corpus in `pkgs/morphir-elm/conformance/projects`. Run `mise run workbench:samples` to
regenerate them; CI fails when the committed assets differ from its output.

## Folder import

The local worker accepts `{"operation": "import-folder", "files": [{"path", "content"}]}` with the text files of a
folder. A common leading folder (as `webkitdirectory` gives, `rentals/morphir.json`) is removed first. The
folder's `morphir.json` is read with the CLI's discovery rules (`name`, `sourceDirectory`, `exposedModules`;
`dependencies` give a warning). The reply is `{"success": true, "project": {"name", "languageId": "elm",
"exposedModules", "files"}, "warnings", "skipped"}`: the `.elm` files under the source directory, re-rooted to
`src/`, and the number of other files left out. The reply's project is a copy; nothing is written back.

A failure is `{"success": false, "message": "<code>: <text>"}` with one of `workbench.folder_without_morphir_json`,
`workbench.folder_too_large` (more than 2,000 files or 16 MiB of text), `workbench.folder_configuration`
(the manifest, the package name or a path is not valid) and `workbench.folder_without_sources`.

## Typed terminal outcomes

Local typed function evaluation emits validated Workbench `0.1.0-draft.5` terminal
evidence after strict invocation planning. A shared outcome component shows
returned values, SDK model errors, evaluation failures and separate cleanup
evidence in the result area and bottom Output/Diagnostics panels. Ordinary
`Result.Err` remains returned data. Cleanup errors leave the value editor visible.

The receiver decodes bounded evidence once, binds it to the expected call identity
and prepares canonical value/structured views independently of a legacy success
flag. Invalid evidence rejects; history retains at most 50 call previews with
4,000 UTF-16 units each, while the current Result JSON retains the exact value.
Input errors, stale results and late replies keep their existing handling.

The browser and packaged Proton share the same component and acceptance workflow.
Tests exercise actual typed values/SDK errors and explicit failure, cleanup and
cancellation evidence fixtures. Connected v1 has no new job or cancellation RPC;
local cancellation still stops/discards the worker operation. Native provider
acquisition/disposal and authoritative daemon job transitions are subsequent work.

## Authenticated evaluation jobs

Build the app first, then explicitly enable the gateway's bounded Scheme provider:

```sh
MORPHIR_WORKBENCH_HOST_URL=http://127.0.0.1:HOST_PORT MORPHIR_WORKBENCH_JOBS=1 mise exec -- bun run --cwd apps/morphir-workbench dev
```

Authenticate through the upstream one-use `/launch` URL with its origin changed
to `http://127.0.0.1:5173`, as above. The gateway serves the shared UI and the
exact `morphir/workbench/host` version `0.1.0-draft.1` endpoints at one origin.
Every job request authenticates the HttpOnly cookie against the real upstream
`/api/session`. The gateway selects its own `moonbit-scheme` provider; it does
not claim the Rust host's compiler provider can evaluate or grant metadata access.
With the flag absent, connected v1 retains its existing behavior.

Import the typed pricing fixture and evaluate a public entry with fields,
JSON or Ion. The UI captures one immutable model/entry/input snapshot and binds
its cursor to the authenticated host, session, provider, job and snapshot.
`finos/morphir-engine/execution/jobs` owns authoritative receipts; the portable
`finos/morphir-execution/jobs` cursor validates incoming evidence. JavaScript handles
HTTP and worker scheduling, while shared MoonBit code validates values and receipts.
Private host code is built outside the public `dist` directory.

The provider runs at most two isolated Node workers at once, with a 128 MiB
V8 old-generation limit and a 30-second execution deadline. This is not a total
process-memory quota. It retains at most eight
jobs within the owner's 16 MiB serialized-evidence budget. Terminal jobs require
explicit release; the UI releases them after validating their evidence. The raw
HTTP body and receipt each have a 1 MiB limit. Duplicate JSON keys and invalid
UTF-8 reject during framing validation. Ion uses the library's flat lexer to reject more
than 300,000 tokens or structural depth above 512 before recursive parsing;
typed values still obey depth 64 and 100,000-node/code-unit limits.

Cancel acknowledges intent before worker termination and cleanup. A captured
returned value can win the race. A lost HTTP reply never creates terminal
execution evidence. The UI retains a known job while disconnected and offers
**Reconnect / resume** only for a newly authenticated identical offer. Resume
queries the same identity without submitting again. A lost submission response
has unknown acceptance, so blind resubmission is blocked. Retention is in memory;
owner restart, browser reload recovery and durable retry are separate work.

The bottom Output and Diagnostics panels show validated terminal evidence,
including ordinary `Result.Err`, SDK model errors and separate cleanup failures.
Editing inputs marks earlier output outdated while the accepted snapshot stays
unchanged. Model replacement is blocked while a job needs reconciliation, including a
disconnected terminal job whose release reply was lost. The latest host evaluation
retains its input draft and full result across declaration navigation. Returning
to that declaration preserves input edits and the result's outdated marker; a new
host evaluation replaces this single retained evaluation.

Run the real-host browser acceptance with jobs enabled:

```sh
mise run test:workbench-live-host -- --host-bin /absolute/path/to/morphir --jobs
```

Add `--desktop-bin '/absolute/path/to/Morphir Workbench.app/Contents/MacOS/morphir-workbench'`
to run the same flow in the packaged Proton app. These optional checks require
the existing Rust binary and, for desktop, a packaged app. They exercise real
cookie authentication, exact Decimal fields/JSON/Ion results, Result.Err, SDK
errors, cancellation, disconnected-query reconciliation and stale-input output.
They do not add an evaluation or cancellation method to connected JSON-RPC v1.

## Projects in the browser

Each language keeps one project (its files, package name and exposed modules) in this browser's `localStorage`, under
`morphir-workbench.project.<language>.v1`. A change is saved 600 ms after the last edit. The workbench restores the
saved projects when it starts in local mode; a saved project that no longer parses is ignored and the Logs say so.
When the browser refuses the save (a private window, a full quota), "Not saved" shows under the project explorer and
the project stays in the page. "Reset project" (in the explorer's More actions menu and the command palette) asks
inline, then restores the default project of the language and removes the saved copy. Nothing leaves the browser: a folder import is a copy, and connected mode (a Morphir host) does not use
this storage.

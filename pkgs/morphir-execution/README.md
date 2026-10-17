# Morphir execution contracts

Portable, versioned invocation values and observations. This module has no process,
filesystem, clock or global logging dependencies. The engine accepts a host-owned
execution provider and an optional evaluator. Generated drivers import this module
and the generated library.

The `morphir-invocations-v1` profile supports exact Int and Decimal, Bool, Unit,
Float64 bits, SDK UTF-16 Text/Character, records, tuples, lists, nongeneric custom
types, Maybe and Result. Typed manifests and generated codecs use the generator's
existing lowering information. Recursive custom types refer to a separate type
registry. Boundary functions are rejected; closures remain supported inside models.

Ion text and binary use native Int, Bool and Decimal and `morphir_unit::null`.
Other values use `morphir_value::{type: ..., ...}` with explicit schema fields.
The JSON projection uses the same tagged schema for every value. Int coefficients
and Float64 bits are decimal strings; UTF-16 units are integers from 0 to 65535.
Decimal uses `coefficient` and `exponent`. Float64 uses `bits`, including NaN payloads,
negative zero, infinities and subnormals. Text/Character use `units`, preserving
isolated surrogates and case expansions without Unicode string conversion.

Lists/tuples use `items`. Records use `fields: [{name, value}]`; duplicate, missing
and extra fields are rejected. Custom values use `owner`, `tag` and `items`, checked
against constructor ownership and arity. Maybe uses `case: nothing|just`, and Result
uses `case: ok|err`. Payload cases include `value`. `Result.Err` stays a model value.
Five enumerated SDK errors become `model-error` outcomes with fixed codes; unknown
exceptions remain failures. Model-error values cannot be invocation arguments.

```ion
{
  profile: "morphir-invocations-v1",
  calls: [{
    id: "difference",
    entry: "calls:main#subtract",
    arguments: [9007199254741035, 9007199254740993]
  }]
}
```

Every suite needs distinct, nonempty call IDs and at least one call. The
budgets are 1 MiB encoded input, 1,000 calls, 64 arguments per call, depth 64 and
100,000 value nodes/code units per call. Exact integers have at most 10,000 digits.
Normalized Decimal exponents range from -32 to 10,000; finer precision is rejected
before the SDK can truncate it. These are
acceptance limits, not a streaming parser guarantee.

`PublicEntry` describes a supported public boundary with `name`, `inputs` and
`output`. `validate_invocations(suite, entries, definitions)` validates suite
identities, public allowlist membership, exact arity and argument types before
provider acquisition. The engine and offline Workbench adapter share this API.
It preserves call order and returns the first invalid call or argument.
Output declarations do not constitute output value validation or evaluation.

The entry list and constructor registry must come from a trusted generator or
bounded manifest validation that establishes unique identities, supported
descriptors and complete reference closure. The Workbench draft.3 guard checks
all input/output and unused declarations before decoding a suite. Names alone
do not prove an entry's visibility in a model. The engine supplies optional
trusted rejection diagnostics for unsupported generated entries; these do not
add public entries or override a listed entry.

Observation stages include frontend, parse, declaration profile-check and
expression checking/lowering alongside execution stages. `Scope.observe` accepts an
optional `is_cancelled` predicate so a frontend can classify its own typed cancellation
without replacing the original diagnostic. The predicate defaults to the execution
cancellation error. It must be pure and must not raise.

The observation interface has a cheap disabled guard, explicit context and
host-supplied clocks and IDs. Sinks return a delivery status. Typed sink exceptions are contained by
`Observer.record`; `Observer.isolated(health)` also rejects recursive delivery
and counts accepted, filtered, dropped and unavailable records.
Required execution results never pass through this interface. Default observation
fields contain no model arguments, results, source text, paths or environment.
The current local host adapter records stage observations and bounded duration
histograms. Native OpenTelemetry integration remains a later acceptance gate.

`TraceContext` accepts only bounded W3C version-00 headers with nonzero lowercase
trace/span IDs and flags 00/01. Baggage and tracestate are unsupported. Hosts
provide trace IDs and 16-character span IDs; disabled scopes do not allocate them.
Call correlation contains target, lease, call and attempt. It is excluded from
semantic values and identity inputs. Process durations always use that process's
monotonic clock; wall timestamps indicate observation time and are not used to
subtract clocks across hosts.

Comparison defaults to `morphir-comparison-exact-v1`: Float64 bits must match,
Decimal comparison normalizes trailing zeros, and record field order does not
matter. `morphir-comparison-approximate-v1` requires explicit finite nonnegative
absolute/relative tolerances. Finite Float64 values use
`abs(x-y) <= absolute + relative * max(abs(x), abs(y))`; overflow in this calculation
fails the comparison. Signed zero and non-finite payload bits remain exact.

Optional suite `extensions` hold arbitrary Ion metadata outside semantic values.
Ion preserves their annotations and native types. JSON explicitly projects this
field as `{format: "ion-binary", bytes: [...]}`. Extensions are bounded to 64 KiB,
echoed in outcomes and verified before reporting. Morphir JSON semantic fields are
unchanged. Source-model annotations and lineage remain in generated symbol metadata.

Logs can identify entries, stages and stable codes without values. Metric descriptors
use bounded stage/target/provider/outcome dimensions; correlation IDs and entries
never become labels. The local adapter caps dimension series at 128 and reports
series overflow independently of its 2,048-record queue. Trace context and timing
are validated outside required receipts and identity inputs.

Embedding hosts may separately configure `PayloadCapture` with an explicit redactor
and sink through `process_execution(payload_capture=...)`. Redaction precedes sink
delivery; each record is limited to 16 KiB. Capture is disabled by default and
independent of diagnostic logging. Redaction failures and oversized records return
unavailable/dropped without changing execution results. The CLI does not expose
unredacted payload capture.

## Structured pipeline warnings

The `diagnostics` package carries recoverable warnings with stable codes, related
owners and spans, original and allocated names, and a suggested fix. Its
`morphir-warning-v1` Ion record can be retained as engine provenance independently
of optional observation sinks. Decoding validates records marked with
`morphir_warning`; other provenance is outside this contract. Producer-specific
source coordinates keep their original meaning and do not become checkpoint
coordinates. This diagnostic contract does not authenticate producers or implement
native IR linked-metadata semantics.

## Offline Workbench terminal evidence

`Outcomes` and `TerminalOutcome` describe exact Workbench `0.1.0-draft.5`
evidence independently of the frozen generated-driver receipt. JSON and Ion-text
codecs preserve ordered call IDs, ordinary returned values including typed
Result.Err, five SDK model errors, primary failures, cancellation and a separate
cleanup failure. Failure stages are typed; codes/messages have UTF-16 bounds.
Opaque extension bytes use the existing JSON binary wrapper or an Ion blob.

`validate_outcomes` binds evidence to a validated Suite and public entries, checks
complete call inventory/order and declared outputs, and requires exact metadata
echo. Callers must validate the whole declaration graph before decoding evidence;
the MCK adapter does so. Successful validation includes well-formed failure and
cancellation claims. It does not run/authenticate a job or prove cancellation.
The parent finos/morphir specification and single Rust MCK own independent
expectations and report checking; UI and live-host adoption are separate.

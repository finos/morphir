# Orders WASM controls

[orders-wasm.controls.json](orders-wasm.controls.json) fixes the inputs and expected results for one v4 plain JSON orders generator. Both hosts use the same Extism module and cases. The [session contract](../../mep/model-access.md) defines the wire messages. The [WASM execution profiles](../../mep/wasm-execution-profiles.md) define the byte calls and worker events.

## Prepare each case

Start with a fresh view of the frozen tree at `fixture`. Apply `patchDocuments` as RFC 6902 patches to private copies. Each key is a path relative to the tree root. Add the JSON documents in `addDocuments` at paths that did not exist in the base. Retain the original bytes of every unchanged document. A delivery uses the bytes of its prepared document, with their actual length, lowercase SHA-256 and padded base64. Use the same byte array for the bad delivery and its valid retry.

The redirected case keeps `order.value` at 73 and adds `reserve.value` with 128. It changes the final value's reference to `reserve`. The frozen and 74 cases have their own fixed output bytes. In both, the final value still refers to `order`, which also names a type.

## Drive the live session

Open a fresh guest instance per case. Offer exactly `tuple` and `limits` in `morphir.initialize`, assert they are admitted for target `text` and assert that `capabilities.notificationDelivery` is absent. Send `morphir.initialized` as a notification. Start generation on the admitted tuple with an empty options object and an empty `requiredGuarantees` list.

Assign fresh opaque strings to the session, snapshot, member selection, page cursor and each document ID in every case. Use distinct IDs, with no relationship to a fixture filename or its position on a page. Reserve `wrong-snapshot` for the refusal case. Keep the fixture paths and the ID mapping on the delivery side. Check the JSON-RPC version and the live request ID on every reply.

| Reply to | Assert | Deliver on the next advance |
| --- | --- | --- |
| Start | Continue at round 1 with an inventory request for `root` and the configured root page size. | The frozen root modules in inventory order. Advertise the live domain member selection. |
| Advance 1 | Continue at round 2 with an inventory request for the advertised domain selection, the configured member page size and no cursor. | The typed entries in `domain.firstPage`, with a live `nextCursor`. |
| Advance 2 | Continue at round 3 with the same selection and size, echoing that cursor. | The typed entries in the model's `expect.lastPage`, with no `nextCursor`. |
| Advance 3 | Continue at round 4 with a document request for the live ID of `domain.finalValue` from the final page. | The selected value document containing the reference. |
| Advance 4 | Continue at round 5 with a document request for the live ID of `expect.referencedValue` from a `value` entry matching the reference's package, module and name. | That value document. |
| Advance 5 | Complete with the live session ID and the exact artifact inventory and UTF-8 bytes in `expect.artifacts`. | |

Each continuation echoes the start's session ID, has one outstanding request with a fresh `requestId`, and has empty artifacts and diagnostics. Match each delivery to the observed request ID and the snapshot admitted at start. The final-page and referenced value documents have the configured output type and no inputs. The artifact's sole chunk has offset zero, an end marker and valid length, digest and base64 for the expected bytes. Completion has empty diagnostics. Compare the full artifact inventory, including the path and final newline.

For a case with `beforeValidAdvance`, copy the prepared document delivery at the specified round and apply `patchDelivery` to that copy. Send the bad delivery first. Assert a JSON-RPC error with the configured code and no result. The reply must have no artifacts and the session must stay open. Resend the original valid delivery using a new RPC ID, the same session and round, and the same delivery request ID. Apply the normal assertions for that round and complete the case with the frozen output.

Send `morphir.shutdown` and await its `{}` result before sending `morphir.exit`. Both notifications must bypass `handle`. Make the guest fault on any notification that reaches it so that a silent response alone cannot satisfy this check. Assert no further response or fault, instance termination and, in worker mode, exit status zero while stdin remains open.

## Assembly and execution

The controls point to [orders-generator.wat](fixtures/wasm/orders-generator.wat). Edit [orders-generator.c](fixtures/wasm/orders-generator.c) to change the guest. The freestanding source keeps the JSON parser, base64 codec, SHA-256 and session transitions reviewable. The generated WAT has one fixed Wasm32 page and imports only the five Extism kernel functions it calls.

The WAT was generated with Clang and LLD 23.1.5 and `wabt` 1.0.39. To regenerate it from the repository root, run each command after the preceding command succeeds.

```powershell
$guest = "spec/mck/bounded-generation/fixtures/wasm/orders-generator"
New-Item -ItemType Directory -Force .dev | Out-Null
clang --target=wasm32 -Oz -ffreestanding -nostdlib -Wall -Wextra -Werror -c "$guest.c" -o .dev/orders-compiled.o
wasm-ld --no-entry --initial-memory=65536 --max-memory=65536 -z stack-size=12288 --strip-all -o .dev/orders-compiled.wasm .dev/orders-compiled.o
bun tools/node_modules/wabt/bin/wasm2wat --generate-names .dev/orders-compiled.wasm -o "$guest.wat"
```

Assemble the checked-in WAT with the pinned `wabt` assembler from the [WASM host kit](../../mep/mck/README.md#wasm-host-qualification-corpus). This PowerShell command runs from the repository root with the tools dependencies present.

```powershell
@'
import { assembler, classify, readModule, sha256, surfaceProblems } from "./tools/check-wasm-host-kit.ts";
const kit = "spec/mck/bounded-generation";
const { generator } = await Bun.file(`${kit}/orders-wasm.controls.json`).json();
const contract = await Bun.file("spec/mep/wasm-execution-profiles.json").json();
const wat = `${kit}/${generator.wat}`;
const bytes = (await assembler())(wat, await Bun.file(wat).text());
const shape = readModule(bytes);
if (classify(shape.imports, undefined, contract) !== generator.abi) throw new Error("Unexpected guest ABI");
const problems = surfaceProblems(shape, generator.abi, contract);
if (problems.length) throw new Error(problems.join("\n"));
const digest = sha256(bytes);
if (digest !== generator.sha256) throw new Error(`Expected ${generator.sha256}, got ${digest}`);
const wasm = ".dev/orders-generator.wasm";
await Bun.write(wasm, bytes);
console.log(wasm, digest);
'@ | bun run -
```

Run `bun test tools/check-wasm-host-kit.test.ts --test-name-pattern "shared orders WASM guest"` to assemble the WAT, check its ABI and execute the five controls under the kit's test-only Extism shim. The shim invokes the guest directly and can check that deliberately delivered notifications trap. Host notification routing, instance teardown and runtime-enforced bounds require the worker execution.

Use those assembled bytes for both hosts. The shared execution seam takes a host's `extension worker --help --json` result and passes its `result.buildIdentity` to:

```text
<host> extension worker --abi extism-kernel-v1 --module .dev/orders-generator.wasm --build-identity <id> --request-bytes 8192 --response-bytes 8192 --call-ms 1000 --memory-pages 16 --json
```

Send Content-Length frames through the existing process-session driver, waiting for and inspecting each reply before building the next input. The fixed-frame WASM host corpus sends its inputs up front. Record the actual engine and build identity, module digest, enforced memory and deadline bounds, and observed frame, decoded batch and artifact chunk sizes. An in-process byte-call test can apply the same message assertions and observe instance termination directly.

The inputs and assertions are test data. They provide no host observations or resource receipts.

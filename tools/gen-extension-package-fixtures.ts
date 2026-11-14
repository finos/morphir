// Writes deterministic test data. It neither validates packages nor implements a host.
import { createHash } from "node:crypto";
import { mkdirSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { crc32, deflateRawSync, gzipSync } from "node:zlib";

const VERSION = "0.1.0-preview.3";
// The package tree manifest format did not change in preview.2 or preview.3, so its header keeps the version it was defined at.
const TREE_VERSION = "0.1.0-preview.1";
const schemaBase = `https://morphir.finos.org/schemas/extensions/${VERSION}/`;
const sha = (bytes: Uint8Array | string) => createHash("sha256").update(bytes).digest("hex");
const u16 = (n: number) => { const b = Buffer.alloc(2); b.writeUInt16LE(n); return b; };
const u32 = (n: number) => { const b = Buffer.alloc(4); b.writeUInt32LE(n >>> 0); return b; };
const u64 = (n: number) => { const b = Buffer.alloc(8); b.writeBigUInt64LE(BigInt(n)); return b; };
type Entry = { name: string; data?: Buffer; mode?: number; type?: string; flags?: number; method?: number; localName?: string; crc?: number; compressed?: Buffer; size?: number; prefix?: string; base256?: boolean };

function zip(entries: Entry[], options: { zip64?: boolean; reverseCentral?: boolean; timestamp?: number } = {}): Buffer {
 const locals: Buffer[] = [], central: Buffer[] = []; let offset = 0;
 for (const e of entries) {
  const name = Buffer.from(e.name), localName = Buffer.from(e.localName ?? e.name);
  const data = e.data ?? Buffer.alloc(0), method = e.method ?? 0, flags = e.flags ?? 0;
  const compressed = e.compressed ?? (method === 8 ? deflateRawSync(data, { level: 9 }) : data);
  const size = e.size ?? data.length, crc = e.crc ?? crc32(data);
  const extra = options.zip64 ? Buffer.concat([u16(1), u16(16), u64(size), u64(compressed.length)]) : Buffer.alloc(0);
  const size32 = options.zip64 ? 0xffffffff : size, compressed32 = options.zip64 ? 0xffffffff : compressed.length;
  const local = Buffer.concat([u32(0x04034b50), u16(options.zip64 ? 45 : 20), u16(flags), u16(method), u16(0), u16(options.timestamp ?? 33), u32(crc), u32(compressed32), u32(size32), u16(localName.length), u16(extra.length), localName, extra, compressed]);
  const attributes = ((e.mode ?? (e.name.endsWith("/") ? 0o040755 : 0o100644)) << 16) >>> 0;
  const extraCentral = options.zip64 ? Buffer.concat([u16(1), u16(24), u64(size), u64(compressed.length), u64(offset)]) : Buffer.alloc(0);
  central.push(Buffer.concat([u32(0x02014b50), u16(0x032d), u16(options.zip64 ? 45 : 20), u16(flags), u16(method), u16(0), u16(options.timestamp ?? 33), u32(crc), u32(compressed32), u32(size32), u16(name.length), u16(extraCentral.length), u16(0), u16(0), u16(0), u32(attributes), u32(options.zip64 ? 0xffffffff : offset), name, extraCentral]));
  locals.push(local); offset += local.length;
 }
 if (options.reverseCentral) central.reverse();
 const cd = Buffer.concat(central), count = entries.length;
 const zip64 = options.zip64 ? Buffer.concat([u32(0x06064b50), u64(44), u16(45), u16(45), u32(0), u32(0), u64(count), u64(count), u64(cd.length), u64(offset), u32(0x07064b50), u32(0), u64(offset + cd.length), u32(1)]) : Buffer.alloc(0);
 const end = Buffer.concat([u32(0x06054b50), u16(0), u16(0), u16(options.zip64 ? 0xffff : count), u16(options.zip64 ? 0xffff : count), u32(options.zip64 ? 0xffffffff : cd.length), u32(options.zip64 ? 0xffffffff : offset), u16(0)]);
 return Buffer.concat([...locals, cd, zip64, end]);
}

function tarHeader(e: Entry): Buffer {
 const h = Buffer.alloc(512), data = e.data ?? Buffer.alloc(0);
 h.write(e.name, 0, 100, "utf8");
 const octal = (offset: number, length: number, value: number) => h.write(value.toString(8).padStart(length - 1, "0") + "\0", offset, length, "ascii");
 octal(100, 8, e.mode ?? 0o644); octal(108, 8, 0); octal(116, 8, 0);
 if (e.base256) { h.writeBigUInt64BE(BigInt(e.size ?? data.length), 128); h[124] = 0x80; }
 else octal(124, 12, e.size ?? data.length);
 octal(136, 12, 0); h.fill(32, 148, 156); h.write(e.type ?? "0", 156, 1, "ascii");
 h.write("ustar\0", 257, 6, "ascii"); h.write("00", 263, 2, "ascii");
 if (e.prefix) h.write(e.prefix, 345, 155, "ascii");
 const sum = h.reduce((n, b) => n + b, 0); h.write(sum.toString(8).padStart(6, "0") + "\0 ", 148, 8, "ascii"); return h;
}
function tar(entries: Entry[], end = true): Buffer {
 return Buffer.concat([...entries.flatMap(e => { const data = e.data ?? Buffer.alloc(0); return [tarHeader(e), data, Buffer.alloc((512 - data.length % 512) % 512)]; }), ...(end ? [Buffer.alloc(1024)] : [])]);
}
function gz(data: Buffer): Buffer {
 const bytes = gzipSync(data, { level: 9 });
 // RFC 1952 OS=255 means unspecified. zlib otherwise writes the build OS here,
 // making identical tar bytes acquire different archive digests on Windows/Linux.
 bytes[9] = 255;
 return bytes;
}
function pax(key: string, value: string): Buffer {
 const content = ` ${key}=${value}\n`; let length = content.length + 1;
 while (String(length).length + content.length !== length) length = String(length).length + content.length;
 return Buffer.from(`${length}${content}`);
}
type TreeFile = { path: string; data: Buffer };
function treeManifest(files: TreeFile[], entryPoint: string, executables: string[] = []): string {
 return `morphir-package-tree ${TREE_VERSION}\n` + [...files].sort((a, b) => Buffer.compare(Buffer.from(a.path), Buffer.from(b.path))).map(f => `${f.path === entryPoint || executables.includes(f.path) ? "x" : "f"} ${f.data.length} ${sha(f.data)} ${f.path}\n`).join("");
}

type Package = { format: string; entryPoint: string; treeSha256: string; root?: string; executables?: string[] };
type Case = { id: string; scenarios: string[]; input: Record<string, unknown>; expected: Record<string, unknown>; schemaDocuments?: unknown[] };
const cases: Case[] = [];
const run = Buffer.from("run!\n"), dll = Buffer.from("dll"), empty = Buffer.alloc(0);
const files = [{ path: "run", data: run }, { path: "lib/a.dll", data: dll }, { path: "docs/read me.txt", data: empty }, { path: "tools/helper", data: run }];
const manifest = treeManifest(files, "run", ["tools/helper"]);
const packageFor = (format: string): Package => ({ format, root: "bundle", entryPoint: "run", executables: ["tools/helper"], treeSha256: sha(manifest) });
const entries = [{ name: "bundle/", type: "5", mode: 0o040755 }, ...files.map(f => ({ name: `bundle/${f.path}`, data: f.data }))];
const singleManifest = treeManifest([{ path: "run", data: run }], "run");
const singlePackage = (format: string): Package => ({ format, entryPoint: "run", treeSha256: sha(singleManifest) });

function build(output: string): void {
 mkdirSync(join(output, "fixtures"), { recursive: true });
 function archive(id: string, bytes: Buffer, pkg: Package, code?: string, entry: string | null = null, scenarios: string[] = [], expectedManifest?: string): Case {
  const filename = `${id}.${pkg.format === "zip" ? "zip" : "tgz"}`;
  writeFileSync(join(output, "fixtures", filename), bytes);
  const c: Case = { id, scenarios, input: { operation: "install-package", archive: `fixtures/${filename}`, bytesSha256: sha(bytes), archiveLength: bytes.length, artifact: { runtime: "process", platform: "x86_64-unknown-linux-gnu", filename, sha256: sha(bytes), package: pkg }, critical: ["artifacts.package"] }, expected: code ? { outcome: "refuse", code: `package.${code}`, entry } : { outcome: "accept", manifest: expectedManifest ?? singleManifest, treeSha256: pkg.treeSha256 } };
  cases.push(c); return c;
 }
 const goodZip = archive("valid-zip", zip(entries), packageFor("zip"), undefined, null, ["A process package", "A tree with an empty file and a space in a name", "A lock records both digests", "Two hosts agree on every case"], manifest);
 archive("valid-tar", gz(tar(entries)), packageFor("tar.gz"), undefined, null, [], manifest);
 archive("valid-zip64", zip(entries, { zip64: true }), packageFor("zip"), undefined, null, [], manifest);
 archive("valid-deflate", zip([{ name: "run", data: run, method: 8 }]), singlePackage("zip"));
 archive("valid-metadata-changed", zip(entries.map(e => ({ ...e, mode: e.name.endsWith("/") ? 0o040700 : 0o100755 })), { timestamp: 123 }), packageFor("zip"), undefined, null, ["Archive metadata does not change the digest"], manifest);
 archive("valid-pax-path", gz(tar([{ name: "pax", type: "x", data: pax("path", "run") }, { name: "ignored", data: run }])), singlePackage("tar.gz"));
 archive("valid-gnu-long-name", gz(tar([{ name: "long", type: "L", data: Buffer.from("lib/a-very-long-name.dll\0") }, { name: "././@LongLink", data: run }])), { format: "tar.gz", entryPoint: "lib/a-very-long-name.dll", treeSha256: sha(treeManifest([{ path: "lib/a-very-long-name.dll", data: run }], "lib/a-very-long-name.dll")) }, undefined, null, ["A GNU long name"], treeManifest([{ path: "lib/a-very-long-name.dll", data: run }], "lib/a-very-long-name.dll"));
 archive("valid-leading-dot", gz(tar([{ name: "./", type: "5" }, { name: "./run", data: run }, { name: "./lib/a.dll", data: dll }])), { format: "tar.gz", entryPoint: "run", treeSha256: sha(treeManifest([{ path: "run", data: run }, { path: "lib/a.dll", data: dll }], "run")) }, undefined, null, ["An archive made from inside its directory"], treeManifest([{ path: "run", data: run }, { path: "lib/a.dll", data: dll }], "run"));
 archive("valid-base256", gz(tar([{ name: "run", data: run, base256: true }])), singlePackage("tar.gz"));
 archive("valid-ustar-prefix", gz(tar([{ name: "run", prefix: "bin", data: run }])), { format: "tar.gz", entryPoint: "bin/run", treeSha256: sha(treeManifest([{ path: "bin/run", data: run }], "bin/run")) }, undefined, null, [], treeManifest([{ path: "bin/run", data: run }], "bin/run"));

 const badZip = (id: string, e: Entry[], code: string, entry: string | null, scenarios: string[] = []) => archive(id, zip(e), singlePackage("zip"), code, entry, scenarios);
 badZip("encrypted", [{ name: "run", data: run, flags: 1 }], "zip_unsupported", "run", ["An encrypted entry"]);
 badZip("zip-crc", [{ name: "run", data: run, crc: 0 }], "zip_crc", "run");
 badZip("local-name", [{ name: "run", localName: "../run", data: run }], "zip_header_mismatch", "run", ["A local header that lies about its name"]);
 archive("zip-prefix", Buffer.concat([Buffer.from("MZ"), zip([{ name: "run", data: run }])]), singlePackage("zip"), "zip_layout", null, ["A self-extracting prefix"]);
 archive("central-order", zip([{ name: "CON", data: run }, { name: "../x", data: run }], { reverseCentral: true }), singlePackage("zip"), "parent_component", "../x", ["Central-directory order decides the first fault"]);
 badZip("zip-link", [{ name: "lib/current", data: run, mode: 0o120777 }], "link_entry", "lib/current", ["A link that looks like a file"]);
 badZip("zip-device", [{ name: "run", mode: 0o020644 }], "special_entry", "run");
 badZip("zip-type", [{ name: "run", mode: 0o040755 }], "entry_type_mismatch", "run");
 badZip("directory-data", [{ name: "lib/", data: Buffer.alloc(10) }], "directory_with_data", "lib/", ["A directory with data"]);
 for (const [id, name, code, scenario] of [
  ["non-ascii", "notes/café.txt", "non_ascii_name", "A non-ASCII name"],
  ["backslash", "a\\b.dll", "backslash", "Traversing and absolute paths"],
  ["absolute", "/etc/passwd", "absolute_path", "Traversing and absolute paths"],
  ["drive", "C:/x.dll", "drive_letter", "Traversing and absolute paths"],
  ["empty-component", "a//b.dll", "empty_or_dot_component", "Traversing and absolute paths"],
  ["parent", "../evil.dll", "parent_component", "Traversing and absolute paths"],
  ["reserved", "lib/a:b", "reserved_character", "Windows names that cannot be stored"],
  ["trailing-dot", "notes.", "trailing_dot_or_space", "Windows names that cannot be stored"],
  ["trailing-space", "notes ", "trailing_dot_or_space", "Windows names that cannot be stored"],
  ["device", "lib/CON.dll", "device_name", "Windows names that cannot be stored"],
  ["com-device", "com1", "device_name", "Windows names that cannot be stored"],
  ["path-length", "a".repeat(121), "path_length", "A tree path one past the limit"],
  ["depth", Array(17).fill("a").join("/"), "nesting_depth", "A tree path one past the limit"],
  ["parent-before-device", "../CON", "parent_component", "An entry that breaks two rules"]
 ] as const) badZip(id, [{ name, data: run }], code, name, [scenario]);
 badZip("duplicate", [{ name: "run", data: run }, { name: "run", data: run }], "duplicate_entry", "run", ["Case and file-directory collisions"]);
 badZip("case-file", [{ name: "lib/A.dll", data: run }, { name: "lib/a.dll", data: run }], "case_collision", "lib/a.dll", ["Case and file-directory collisions"]);
 badZip("case-directory", [{ name: "Lib/x.dll", data: run }, { name: "lib/y.dll", data: run }], "case_collision", "lib/y.dll", ["Case and file-directory collisions"]);
 badZip("file-directory", [{ name: "lib/x.dll", data: run }, { name: "lib/x.dll/y", data: run }], "file_directory_conflict", "lib/x.dll/y", ["Case and file-directory collisions"]);
 archive("outside-root", zip([{ name: "fsharp-frontend/morphir-fsharp-frontend.exe", data: run }, { name: "README.txt", data: run }]), { ...singlePackage("zip"), root: "fsharp-frontend", entryPoint: "morphir-fsharp-frontend.exe" }, "outside_root", "README.txt", ["A file outside the declared root"]);
 badZip("entry-count", Array.from({ length: 4097 }, (_, i) => ({ name: `d${i}/` })), "entry_count", "d4096/");

 const badTar = (id: string, e: Entry[], code: string, entry: string | null, scenarios: string[] = []) => archive(id, gz(tar(e)), singlePackage("tar.gz"), code, entry, scenarios);
 archive("two-gzip-members", Buffer.concat([gz(tar([{ name: "run", data: run }])), gz(Buffer.alloc(0))]), singlePackage("tar.gz"), "gzip_layout", null, ["Two gzip members"]);
 archive("missing-tar-end", gz(tar([{ name: "run", data: run }], false)), singlePackage("tar.gz"), "tar_layout", null, ["A missing end of archive"]);
 badTar("tar-contiguous", [{ name: "run", type: "7" }], "tar_unsupported", "run", ["Contiguous and global headers"]);
 badTar("tar-global", [{ name: "global", type: "g" }], "tar_unsupported", "global", ["Contiguous and global headers"]);
 badTar("tar-sparse-pax", [{ name: "pax", type: "x", data: pax("GNU.sparse.map", "0,5") }, { name: "run", data: run }], "tar_unsupported", "run", ["Contiguous and global headers"]);
 badTar("huge-pax-header", [{ name: "pax", type: "x", size: 2 * 1024 * 1024 }], "tar_header_too_large", "pax", ["A huge pax header"]);
 badTar("link-before-parent", [{ name: "../x", type: "2" }], "link_entry", "../x", ["A link with a traversing name"]);
 const trailer = gz(tar([{ name: "../x", data: run }])); trailer[trailer.length - 8] = trailer[trailer.length - 8]! ^ 1;
 archive("entry-before-gzip-trailer", trailer, singlePackage("tar.gz"), "parent_component", "../x", ["A bad gzip trailer after a bad entry"]);
 const wrongTrailer = gz(tar([{ name: "run", data: run }])); wrongTrailer[wrongTrailer.length - 8] = wrongTrailer[wrongTrailer.length - 8]! ^ 1;
 archive("gzip-trailer", wrongTrailer, singlePackage("tar.gz"), "gzip_layout");

 // Real compressed boundary data. These archives are small on disk but intentionally expand
 // to the stated bounds. Integrity tests hash bytes; only a bounded host test decompresses them.
 const zeros = Buffer.alloc(256 * 1024 * 1024 + 1);
 const compressedFull = deflateRawSync(zeros.subarray(0, -1), { level: 9 });
 const fullCrc = crc32(zeros.subarray(0, -1));
 badZip("file-too-large", [{ name: "run", method: 8, compressed: deflateRawSync(zeros, { level: 9 }), size: zeros.length, crc: crc32(zeros) }], "file_too_large", "run");
 badZip("unpacked-size", [...["run", "b", "c", "d"].map(name => ({ name, method: 8, compressed: compressedFull, size: zeros.length - 1, crc: fullCrc })), { name: "e", data: Buffer.from([0]) }], "unpacked_size", "e", ["A decompression bomb"]);
 const singleBytes = zip([{ name: "run", data: run }]);
 archive("missing-entry-point", singleBytes, { ...singlePackage("zip"), entryPoint: "missing", treeSha256: "0".repeat(64) }, "entry_point_missing", "missing", ["A missing entry point before a wrong digest"]);
 const windows = archive("windows-not-exe", zip([{ name: "run.cmd", data: run }]), { ...singlePackage("zip"), entryPoint: "run.cmd" }, "entry_point_not_exe", "run.cmd", ["A Windows entry point that is not an executable"]);
 (windows.input.artifact as any).platform = "x86_64-pc-windows-msvc";
 archive("missing-executable", singleBytes, { ...singlePackage("zip"), executables: ["absent"] }, "executable_missing", "absent");
 archive("wrong-tree", singleBytes, { ...singlePackage("zip"), treeSha256: "0".repeat(64) }, "tree_digest_mismatch", null, ["A wrong tree digest"]);
 const digestFirst = archive("digest-before-entry", zip([{ name: "../x", data: run }]), singlePackage("zip"), "archive_digest_mismatch", null, ["A bad archive is refused before its entries"]);
 (digestFirst.input.artifact as any).sha256 = "0".repeat(64);
 cases.push({ id: "archive-too-large", scenarios: [], input: { operation: "install-package", archiveLength: 268435457 }, expected: { outcome: "refuse", code: "package.archive_too_large", entry: null } });
 for (const [id, code, scenario, patch] of [
  ["wasm-package", "runtime", "A WASM artifact cannot be a package", { runtime: "wasm" }],
  ["format-mismatch", "archive_format", "A format that does not match the file name", { filename: "frontend.tgz" }],
  ["not-critical", "not_critical", "A package that is not marked critical", {}],
  ["unsupported-host", "unsupported", "A host without package support", {}]
 ] as const) cases.push({ id, scenarios: [scenario], input: { ...goodZip.input, operation: "read-descriptor", artifact: { ...(goodZip.input.artifact as object), ...patch }, ...(id === "not-critical" ? { critical: [] } : {}), ...(id === "unsupported-host" ? { readerSupportsPackages: false } : {}) }, expected: { outcome: "refuse", code: `package.${code}`, entry: null } });
 {
 // A descriptor may offer both runtimes. The selection cases are data for a host adapter, not executed here.
 const processArtifact = { ...(goodZip.input.artifact as object) };
 const wasmArtifact = { runtime: "wasm", filename: "extension.wasm", sha256: sha(run) };
 const mixed = [processArtifact, wasmArtifact];
 cases.push({ id: "mixed-runtimes", scenarios: ["A mixed descriptor is accepted"], input: { operation: "read-descriptor", artifacts: mixed, critical: ["artifacts.package"] }, expected: { outcome: "accept", shape: "mixed" } });
 cases.push({ id: "select-matching-process", scenarios: ["A host that runs both selects the matching process artifact and the lock records it"], input: { operation: "select-artifact", hostPlatform: "x86_64-unknown-linux-gnu", hostRuntimes: ["process", "wasm"], artifacts: mixed, critical: ["artifacts.package"] }, expected: { outcome: "accept", selected: { runtime: "process", filename: (processArtifact as { filename: string }).filename }, lock: { runtime: "process", platform: { os: "linux", arch: "x86_64" } } } });
 cases.push({ id: "select-wasm-fallback", scenarios: ["A host with no matching process artifact selects the WASM artifact"], input: { operation: "select-artifact", hostPlatform: "aarch64-apple-darwin", hostRuntimes: ["process", "wasm"], artifacts: mixed, critical: ["artifacts.package"] }, expected: { outcome: "accept", selected: { runtime: "wasm", filename: "extension.wasm" }, lock: { runtime: "wasm" } } });
}
{
 // A NuGet package is a ZIP file. A feed signs it after packing, so only .signature.p7s differs between the copies;
 // the tree is the entries under root, so treeSha256 is the same for both.
 const nugetRoot = "morphir/linux-x64";
 const nugetFiles = [{ path: "run", data: run }, { path: "lib/a.dll", data: dll }];
 const nugetManifest = treeManifest(nugetFiles, "run");
 const nugetPackage: Package = { format: "nupkg", root: nugetRoot, entryPoint: "run", treeSha256: sha(nugetManifest) };
 const nugetFilename = "finos.morphir.example.0.6.0.nupkg";
 const nupkg = (signature: string) => zip([
  { name: "_rels/.rels", data: Buffer.from("<Relationships/>") },
  { name: "finos.morphir.example.nuspec", data: Buffer.from("<package/>") },
  { name: `${nugetRoot}/run`, data: run, method: 8 },
  { name: `${nugetRoot}/lib/a.dll`, data: dll, method: 8 },
  { name: "package/services/metadata/core-properties/1.psmdcp", data: Buffer.from("<coreProperties/>") },
  { name: "[Content_Types].xml", data: Buffer.from("<Types/>") },
  { name: ".signature.p7s", data: Buffer.from(signature) },
 ]);
 for (const [id, signature] of [["nupkg-packed", "author signature"], ["nupkg-repository-signed", "repository countersignature"]] as const) {
  const bytes = nupkg(signature);
  writeFileSync(join(output, "fixtures", `${id}.nupkg`), bytes);
  cases.push({ id, scenarios: ["A repository signature does not change the tree"], input: { operation: "install-package", archive: `fixtures/${id}.nupkg`, bytesSha256: sha(bytes), archiveLength: bytes.length, artifact: { runtime: "process", platform: "x86_64-unknown-linux-gnu", filename: nugetFilename, package: nugetPackage }, critical: ["artifacts.package"] }, expected: { outcome: "accept", manifest: nugetManifest, treeSha256: nugetPackage.treeSha256 } });
 }
 cases.push({ id: "nupkg-upper-case-filename", scenarios: ["A NuGet package file name in upper case"], input: { operation: "read-descriptor", artifact: { runtime: "process", platform: "x86_64-unknown-linux-gnu", filename: "Finos.Morphir.Example.0.6.0.nupkg", package: nugetPackage }, critical: ["artifacts.package"] }, expected: { outcome: "refuse", code: "package.archive_format", entry: null } });
}
cases.push({ id: "raw-executable", scenarios: ["A raw executable is unchanged"], input: { operation: "read-descriptor", artifact: { runtime: "process", filename: "morphir-scala-elm-linux-amd64-0.5.0-M13", sha256: sha(run), platform: "x86_64-unknown-linux-gnu" } }, expected: { outcome: "accept", shape: "single-file" } });
 cases.push({ id: "archive-without-package", scenarios: ["An executable shipped inside an archive"], input: { operation: "read-descriptor", artifact: { runtime: "process", filename: "morphir-elm-extension-0.4.1-x86_64-unknown-linux-gnu.tgz", sha256: sha(run), platform: "x86_64-unknown-linux-gnu" } }, expected: { outcome: "refuse", code: "package.archive_without_package", entry: null } });
 cases.push({ id: "tree-changed", scenarios: ["A file is missing"], input: { operation: "activate-package", package: packageFor("zip"), manifest, tree: files.filter(f => f.path !== "lib/a.dll").map(f => ({ path: f.path, size: f.data.length, mode: f.path === "run" || f.path === "tools/helper" ? "0555" : "0444" })) }, expected: { outcome: "refuse", code: "package.tree_changed", entry: "lib/a.dll" } });
 const verifiedTree = files.map(f => ({ path: f.path, bytes: [...f.data], mode: f.path === "run" || f.path === "tools/helper" ? "0555" : "0444" }));
 const existingTree = structuredClone(verifiedTree); existingTree[0]!.bytes[0] = existingTree[0]!.bytes[0]! ^ 1;
 const reuseInput = { operation: "publish-package", package: packageFor("zip"), manifest, verifiedTree, existingTree, stateLock: "exclusive", leaseFileIdentity: "existing-lease-1" };
 cases.push({ id: "reuse-same-size-corruption", scenarios: ["A same-size changed tree is not reused at install"], input: { ...reuseInput, existingLease: "free" }, expected: { outcome: "accept", reuseExisting: false, repair: "replace-with-verified-staging", fullHashMismatch: "run", lease: "exclusive-nonwaiting-before-mutation", leaseFileIdentity: "existing-lease-1", recordedTree: verifiedTree } });
 cases.push({ id: "repair-leased-corrupt-tree", scenarios: ["A corrupt tree with a live lease is left unchanged"], input: { ...reuseInput, existingLease: "shared-live-guest" }, expected: { outcome: "refuse", code: "package.publish_busy", entry: null, fullHashMismatch: "run", mutations: [], reuseExisting: false, leaseFileIdentity: "existing-lease-1", staging: "retained-for-cleanup", lockAndCatalog: "unchanged" } });
 cases.push({ id: "older-reader-critical", scenarios: ["A host built without this change meets a package"], input: { ...goodZip.input, operation: "read-descriptor", readerUnderstands: ["runtime", "filename", "sha256", "claims"] }, expected: { outcome: "refuse", rule: "critical", file: "release.json", entry: "artifacts.package" } });
 // Whole-document schema examples are data, with every package copy unchanged.
 const claims = { protocolVersions: ["0.2.0-draft.1"], extension: { id: "org.finos.morphir.fsharp-frontend", name: "F# frontend", version: "0.6.0", types: ["frontend"] }, capabilities: { frontend: { languages: [{ id: "fsharp", fileExtensions: [".fs"] }], irVersions: ["4"], compile: true } } };
 const artifact = { ...(goodZip.input.artifact as any), claims }; delete artifact.platform; artifact.platform = "x86_64-unknown-linux-gnu";
 const descriptor = { $schema: schemaBase + "release.schema.json", extensionId: claims.extension.id, shortId: "fsharp-frontend", version: "0.6.0", platformDifferences: "none", artifacts: [artifact], critical: ["artifacts.package"] };
 const platform = { os: "linux", arch: "x86_64" };
 const source = { kind: "local-file", path: `artifacts/${artifact.filename}` };
 const index = { kind: "local-directory", identity: "/repo", revision: "a".repeat(64) };
 const record = { $schema: schemaBase + "index-record.schema.json", id: claims.extension.id, name: claims.extension.name, version: "0.6.0", channels: ["stable"], artifacts: [{ ...artifact, platform, source, args: [], executable: true, claimCheck: "unchecked" }], critical: ["artifacts.package"] };
 const entry = { extensionId: claims.extension.id, name: claims.extension.name, version: "0.6.0", runtime: "process", platform, args: [], digest: artifact.sha256, storePath: `store/extensions/packages/sha256/${artifact.package.treeSha256}/tree/${artifact.package.entryPoint}`, capabilities: ["frontend"], mepVersions: claims.protocolVersions, index, frontend: claims.capabilities.frontend, executable: true, claims, claimCheck: "unchecked", package: artifact.package };
 const catalog = { $schema: schemaBase + "catalog.schema.json", extensions: [entry], critical: ["extensions.package"] };
 const lock = { $schema: schemaBase + "lock.schema.json", selection: { kind: "exact", value: "0.6.0" }, extensionId: entry.extensionId, name: entry.name, version: entry.version, index: { ...index, claims }, source, runtime: entry.runtime, platform, args: [], digest: entry.digest, capabilities: entry.capabilities, mepVersions: entry.mepVersions, frontend: entry.frontend, executable: true, package: artifact.package };
 goodZip.schemaDocuments = [
  { schema: "release.schema.json", valid: true, document: descriptor },
  { schema: "index-record.schema.json", valid: true, document: record },
  { schema: "catalog.schema.json", valid: true, document: catalog },
  { schema: "lock.schema.json", valid: true, document: lock },
  { schema: "release.schema.json", valid: false, document: { ...descriptor, artifacts: [{ ...artifact, runtime: "wasm" }] } },
  { schema: "release.schema.json", valid: false, document: { ...descriptor, artifacts: [{ ...artifact, package: { ...artifact.package, format: "rar" } }] } },
  { schema: "release.schema.json", valid: false, document: { ...descriptor, artifacts: [{ ...artifact, package: { ...artifact.package, treeSha256: null } }] } }
 ];
 goodZip.scenarios.push("A package descriptor validates");
 // Exercise the member policy at every object in the package-bearing documents.
 // These are fixed schema examples, not a behavioral implementation.
 const objectPaths = (value: any, path: (string | number)[] = []): (string | number)[][] => {
  if (Array.isArray(value)) return value.flatMap((v, i) => objectPaths(v, [...path, i]));
  if (!value || typeof value !== "object") return [];
  return [path, ...Object.entries(value).flatMap(([k, v]) => objectPaths(v, [...path, k]))];
 };
 for (const [schema, document, valid] of [["release.schema.json", descriptor, true], ["index-record.schema.json", record, true], ["catalog.schema.json", catalog, true], ["lock.schema.json", lock, false]] as const) {
  for (const path of objectPaths(document)) {
   const copy: any = structuredClone(document); let target = copy;
   for (const key of path) target = target[key];
   target.futureNote = { value: "optional extension metadata" };
   goodZip.schemaDocuments.push({ schema, valid, document: copy });
  }
 }
 const hostTests = [
  { id: "schema-editor", scenarios: [], purpose: "Validate all package-bearing whole documents through the shared schemas." },
  { id: "publish-store", scenarios: ["The F# frontend in the store", "An interrupted unpack is never selected", "Collection cannot run between publication and recording"], purpose: "Use the real store, owner lock and journal; inject interruption at each publication boundary." },
  { id: "read-only", scenarios: ["A guest that writes beside itself"], purpose: "Start a guest on Unix and verify directory mode 0555 prevents its write." },
  { id: "rename-busy", code: "package.publish_busy", scenarios: ["A scanner holds a new file open"], purpose: "Hold a Windows file open and verify no-replace publication retries for at most ten seconds." },
  { id: "repair-lease", code: "package.publish_busy", scenarios: ["A corrupt tree with a live lease is left unchanged", "A same-size changed tree is not reused at install", "Repair retains the existing lease file"], purpose: "With a real guest holding the shared lease, corrupt one byte without changing size. Install fully hashes the existing tree, refuses repair immediately with package.publish_busy, and leaves tree, modes, manifest, lease identity, lock and catalog unchanged. After guest exit, exclusive nonwaiting repair retains the same lease file identity, replaces the tree from verified staging and records only verified bytes." },
  { id: "one-volume", code: "package.store_not_one_volume", scenarios: [], purpose: "Attempt a real cross-volume rename; verify no copy or recording occurs." },
  { id: "launch", scenarios: ["Starting the F# frontend"], purpose: "Observe absolute argv[0], locked arguments and project working directory in the started guest." },
  { id: "full-verification", scenarios: ["A changed byte is found on request"], purpose: "Modify one byte without changing size; explicit full verification reports package.tree_changed with its path." },
  { id: "windows-path", code: "package.install_path_too_long", scenarios: ["A long user name on Windows"], purpose: "Check real absolute UTF-16 file and directory limits before publication." },
  { id: "leases", scenarios: ["Two sessions share a package", "The host crashes while its guest runs on Unix", "A guest leaves a child behind", "Uninstall while running", "A package in use is kept"], purpose: "Two processes, inherited Unix lease and process group, or Windows no-breakaway job; collection retains every live leased tree." },
  { id: "generation-guard", scenarios: ["A home with a toolchain generation"], purpose: "Put a real generation receipt under toolchains/generations and verify explicit collection removes nothing." },
  { id: "trust", scenarios: ["A signed executable inside an unsigned release"], purpose: "Use a signed entry point from unauthenticated local content; verify signatures inside the archive grant no publisher trust." }
 ];
 writeFileSync(join(output, "package-cases.json"), JSON.stringify({ familyVersion: VERSION, description: "Archive inputs and fixed expectations. No code in this corpus is executed. Case entry names are effective names after archive decoding, before one leading ./ is removed; null means no entry is implicated. Schema examples cover structure only.", cases, hostTests }, null, 2) + "\n");
}

if (import.meta.main) {
 const args = process.argv.slice(2); const i = args.indexOf("--output");
 if (args.length && (i !== 0 || args.length !== 2 || !args[1])) throw new Error("Usage: bun tools/gen-extension-package-fixtures.ts [--output <directory>]");
 build(i === 0 ? args[1]! : "docs/spec/extensions");
}

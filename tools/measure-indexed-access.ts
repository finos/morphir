import { spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import { release } from "node:os";
import path from "node:path";
import { gzipSync } from "node:zlib";
import {
  bindReferenceIndex,
  buildReferenceIndex,
  dictionaryCandidates,
  type ReferenceIndex,
} from "./indexed-access-index";
import { scanReferences, type OccurrenceIdentity } from "./indexed-access-scan";

const root = path.resolve(import.meta.dir, "../spec/experiments/indexed-access");
const read = (file: string) => readFileSync(path.join(root, file));
const controls = JSON.parse(read("controls.json").toString()) as {
  id: string;
  documents: { document: string; file: string }[];
}[];
const queries = JSON.parse(read("queries.json").toString()) as { id: string; fqName: string }[];
const expected = JSON.parse(read("expected.json").toString()) as Record<string, OccurrenceIdentity[]>;
const modes = ["scan", "dictionary", "index"] as const;
type Mode = typeof modes[number];
type Work = { sourceBytes: number; fullDocumentsDecoded: number; referenceValuesDecoded: number };
type Observation = Work & {
  occurrences?: readonly OccurrenceIdentity[];
  candidateDocuments?: readonly string[];
};
const warmSweeps = 64;
const sha256 = (bytes: Uint8Array) => createHash("sha256").update(bytes).digest("hex");
const round = (milliseconds: number) => Number(milliseconds.toFixed(3));
const ordered = (items: readonly OccurrenceIdentity[]) => items.map(item => JSON.stringify(item)).sort();

function child(command: string, args: readonly string[]): string {
  const result = spawnSync(command, args, { encoding: "utf8", windowsHide: true, timeout: 30_000 });
  if (result.error || result.status !== 0) throw new Error(result.error?.message ?? result.stderr);
  return result.stdout;
}

function measure(control: typeof controls[number], mode: Mode) {
  const rssBefore = process.memoryUsage().rss;
  const start = performance.now();
  const sources = control.documents.map(({ document, file }) => ({ document, bytes: read(file) }));
  const sourceBytes = sources.reduce((total, item) => total + item.bytes.byteLength, 0);
  const sourceReadMilliseconds = round(performance.now() - start);

  const prepareStart = performance.now();
  let indexBytes: Buffer | undefined;
  let buildMilliseconds: number | undefined;
  let bindMilliseconds: number | undefined;
  let lookup: (fqName: string) => Observation;
  switch (mode) {
    case "scan": {
      const documents = sources.map(({ document, bytes }) => ({ document, text: bytes.toString("utf8") }));
      lookup = fqName => ({
        occurrences: scanReferences(documents, fqName),
        sourceBytes,
        fullDocumentsDecoded: documents.length,
        referenceValuesDecoded: 0,
      });
      break;
    }
    case "dictionary": {
      const candidates = dictionaryCandidates(sources);
      lookup = fqName => ({
        candidateDocuments: candidates(fqName),
        sourceBytes: 0,
        fullDocumentsDecoded: 0,
        referenceValuesDecoded: 0,
      });
      break;
    }
    case "index": {
      indexBytes = Buffer.from(JSON.stringify(buildReferenceIndex(sources)));
      buildMilliseconds = round(performance.now() - prepareStart);
      const bindStart = performance.now();
      const search = bindReferenceIndex(JSON.parse(indexBytes.toString()) as ReferenceIndex, sources);
      bindMilliseconds = round(performance.now() - bindStart);
      lookup = fqName => {
        const result = search(fqName);
        return {
          occurrences: result.occurrences,
          sourceBytes: result.sourceBytes,
          fullDocumentsDecoded: 0,
          referenceValuesDecoded: result.decodedValues,
        };
      };
      break;
    }
  }
  const prepareMilliseconds = round(performance.now() - prepareStart);
  const rssPrepared = process.memoryUsage().rss;

  const coldStart = performance.now();
  const cold = queries.map(query => lookup(query.fqName));
  const coldMilliseconds = round(performance.now() - coldStart);
  const coldQueries = queries.map(({ id }, position) => {
    const result = cold[position]!;
    const expectedOccurrences = expected[id]!;
    if (result.occurrences) {
      if (!Bun.deepEquals(ordered(result.occurrences), ordered(expectedOccurrences))) {
        throw new Error(`${mode} differs from the frozen result for ${control.id}/${id}`);
      }
      return { id, ...result, correctness: "match" };
    }
    const candidates = result.candidateDocuments!;
    const expectedDocuments = [...new Set(expectedOccurrences.map(occurrence => occurrence.document))];
    const missedDocuments = expectedDocuments.filter(document => !candidates.includes(document));
    const extraDocuments = candidates.filter(document => !expectedDocuments.includes(document));
    return {
      id, ...result, missedDocuments, extraDocuments,
      correctness: missedDocuments.length || extraDocuments.length ? "candidate-mismatch" : "occurrences-unproven",
    };
  });

  const warmStart = performance.now();
  const warmWork = { sourceBytes: 0, fullDocumentsDecoded: 0, referenceValuesDecoded: 0 };
  for (let sweep = 0; sweep < warmSweeps; sweep++) {
    for (const { fqName } of queries) {
      const result = lookup(fqName);
      warmWork.sourceBytes += result.sourceBytes;
      warmWork.fullDocumentsDecoded += result.fullDocumentsDecoded;
      warmWork.referenceValuesDecoded += result.referenceValuesDecoded;
    }
  }
  const warmMilliseconds = round(performance.now() - warmStart);
  const rssAfter = process.memoryUsage().rss;
  const peakRss = process.resourceUsage().maxRSS * 1024;

  return {
    control: control.id,
    mode,
    sources: sources.map(({ document, bytes }) => ({
      document, bytes: bytes.byteLength, gzipBytes: gzipSync(bytes).byteLength, sha256: sha256(bytes),
    })),
    index: indexBytes && {
      bytes: indexBytes.byteLength, gzipBytes: gzipSync(indexBytes).byteLength, sha256: sha256(indexBytes),
    },
    prepare: {
      sourceReadMilliseconds, milliseconds: prepareMilliseconds, buildMilliseconds, bindMilliseconds,
      sourceFileBytesRead: sourceBytes,
      fullDocumentsDecoded: mode === "scan" ? 0 : sources.length,
      indexBytesDecoded: indexBytes?.byteLength ?? 0,
      sourceBytesHashed: mode === "index" ? 2 * sourceBytes : 0,
    },
    cold: { milliseconds: coldMilliseconds, sourceFileBytesRead: 0, queries: coldQueries },
    warm: { sweeps: warmSweeps, milliseconds: warmMilliseconds, sourceFileBytesRead: 0, ...warmWork },
    residentBytes: { before: rssBefore, prepared: rssPrepared, after: rssAfter, peak: peakRss },
  };
}

if (import.meta.main) {
  if (process.argv[2] === "--worker") {
    const mode = modes.find(candidate => candidate === process.argv[3]);
    const control = controls.find(candidate => candidate.id === process.argv[4]);
    if (!mode || !control) throw new Error("Unknown indexed-access measurement mode or control");
    console.log(JSON.stringify(measure(control, mode)));
  } else {
    const revision = child("git", ["rev-parse", "HEAD"]).trim();
    const measurements = controls.flatMap(control => modes.map(mode =>
      JSON.parse(child(process.execPath, [import.meta.path, "--worker", mode, control.id])) as ReturnType<typeof measure>));
    console.log(JSON.stringify({
      revision,
      measuredAtUtc: new Date().toISOString(),
      runtime: { bun: Bun.version, platform: process.platform, architecture: process.arch, osRelease: release() },
      expectedSha256: sha256(read("expected.json")),
      measurements,
    }, null, 2));
  }
}

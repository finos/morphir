import * as util from "util";
import * as fs from "fs";
import { z } from "zod";
import { getUri } from "get-uri";
import { decode, labelToName } from "whatwg-encoding";
import { Readable } from "stream";
import { ResultAsync } from "neverthrow";

const parseDataUrl = require("data-urls");
const fsReadFile = util.promisify(fs.readFile);

const DataUrl = z.string().trim().transform((val, ctx) => {
  const parsed = parseDataUrl(val)
  if (parsed == null) {
    ctx.addIssue({
      code: z.ZodIssueCode.custom,
      message: "Not a valid data url"
    })
    return z.NEVER;
  }
  return parsed;
});

const FileUrl = z.string().trim().url().transform((val, ctx) => {
  if (!val.startsWith("file:")) {
    ctx.addIssue({
      code: z.ZodIssueCode.custom,
      message: "Not a valid file url"
    })
    return z.NEVER;
  }
  return new URL(val);
});

const Url = z.string().url().transform((url) => new URL(url));

const PathOrUrl = z.union([FileUrl, z.string().trim().min(1)]);

const GithubData = z.object({
  owner: z.string(),
  repo: z.string(),
  baseUrl: z.string().optional()
});

const GithubConfig = z.union([GithubData, z.string()]);

const DependencySettings = z.union([DataUrl, FileUrl, z.string().trim()])
const Dependencies = z.array(DependencySettings).default([]);

export const DependencyConfig = z.object({
  dependencies: Dependencies,
  localDependencies: z.array(z.string()).default([]),
  includes: z.array(z.string()).default([]),
});

const IncludeProvided = z.object({
  eventKind: z.literal('IncludeProvided'),
  payload: z.string()
});

const LocalDependencyProvided = z.object({
  eventKind: z.literal('LocalDependencyProvided'),
  payload: z.string()
})

const DependencyProvided = z.object({
  eventKind: z.literal('DependencyProvided'),
  payload: DependencySettings
});

const DependencyEvent = z.discriminatedUnion("eventKind", [
  IncludeProvided,
  LocalDependencyProvided,
  DependencyProvided
]);

const DependencyEvents = z.array(DependencyEvent);

const DependencyConfigToDependencyEvents = DependencyConfig.transform((config) => {
  let events = DependencyEvents.parse([]);
  const includes = config.includes.map((include) => IncludeProvided.parse({ eventKind: "IncludeProvided", payload: include }));
  events.push(...includes);
  const localDeps = config.localDependencies.map((localDependency) => LocalDependencyProvided.parse({ eventKind: "LocalDependencyProvided", payload: localDependency }));
  events.push(...localDeps);
  const deps = config.dependencies.map((dep) => DependencyProvided.parse({ eventKind: "DependencyProvided", payload: dep }));
  events.push(...deps);
  return events;
});


const MorphirDistribution = z.tuple([z.string()]).rest(z.unknown());
const MorphirIRFile = z.object({
  formatVersion: z.number().int(),
  distribution: MorphirDistribution
}).passthrough();

type DataUrl = z.infer<typeof DataUrl>;
type FileUrl = z.infer<typeof FileUrl>;
type Url = z.infer<typeof Url>;
type DependencyConfigToDependencyEvents = z.infer<typeof DependencyConfigToDependencyEvents>
type PathOrUrl = z.infer<typeof PathOrUrl>;
type GithubData = z.infer<typeof GithubData>;
type GithubConfig = z.infer<typeof GithubConfig>;
type DependencyEvent = z.infer<typeof DependencyEvent>;
type MorphirDistribution = z.infer<typeof MorphirDistribution>;
type MorphirIRFile = z.infer<typeof MorphirIRFile>;
export type DependencyConfig = z.infer<typeof DependencyConfig>;

export async function loadAllDependencies(config: DependencyConfig) {
  const events = DependencyConfigToDependencyEvents.parse(config);
  const results = events.map(load);
  const finalResults = await Promise.all(results);
  return finalResults.flatMap((result) => {
    if (result.isOk()) {
      console.error("Successfully loaded dependency", result.value.dependency)
      return result.value.dependency;
    } else {
      console.error("Error loading dependency", result.error);
      return [];
    }
  });
}

function load(event: DependencyEvent) {
  console.error("Loading event", event);
  let source: "dependencies" | "localDependencies" | "includes";
  let payload = event.payload;
  switch (event.eventKind) {
    case 'IncludeProvided':
      source = "includes";
      return loadDependenciesFromString(event.payload, source)
        .map((dependency) => ({ dependency: dependency, source: source, payload: payload }));
    case 'LocalDependencyProvided':
      source = "localDependencies";
      return loadDependenciesFromString(event.payload, source)
        .map((dependency) => ({ dependency: dependency, source: source, payload: payload }));
    case 'DependencyProvided':
      source = "dependencies";
      if (typeof payload === "string") {
        return loadDependenciesFromString(payload, source)
          .map((dependency) => ({ dependency: dependency, source: source, payload: payload }));
      } else {
        return loadDependenciesFromURL(payload, source)
          .map((dependency) => ({ dependency: dependency, source: source, payload: payload }));
      }
  }
}

function loadDependenciesFromString(input: string, source: string) {
  const doWork = async () => {
    let sanitized = input.trim();
    let { success, data } = DataUrl.safeParse(sanitized);
    if (success) {
      console.error("Loading Data url", data);
      const encodingName = labelToName(data.mimeType.parameters.get("charset") || "utf-8") || "UTF-8";
      const bodyDecoded = decode(data.body, encodingName);
      console.error("Data from data url", bodyDecoded);
      return JSON.parse(bodyDecoded);
    }
    let { success: fileSuccess, data: fileData } = FileUrl.safeParse(sanitized);
    if (fileSuccess && fileData !== undefined) {
      console.error("Loading file url", fileData);
      const data = await getUri(fileData);
      const buffer = await toBuffer(data);
      const jsonString = buffer.toString();
      return JSON.parse(jsonString);
    }
    let { success: urlSuccess, data: urlData } = Url.safeParse(sanitized);
    if (urlSuccess && urlData !== undefined) {
      console.error("Loading url", urlData);
      if (urlData.protocol.startsWith("http") || urlData.protocol.startsWith("ftp")) {
        console.error("Loading http or ftp url", urlData);
        const data = await getUri(urlData);
        const buffer = await toBuffer(data);
        const jsonString = buffer.toString();
        return JSON.parse(jsonString);
      }
    }
    throw new DependencyError("Invalid dependency string", input);
  }
  return ResultAsync.fromPromise(doWork(), (err) => new DependencyError("Error loading dependency", source, input, err));
}

function loadDependenciesFromURL(url: URL | Url, source: string) {
  const doWork = async () => {
    const data = await getUri(url);
    const buffer = await toBuffer(data);
    const jsonString = buffer.toString();
    return JSON.parse(jsonString);
  }
  return ResultAsync.fromPromise(doWork(), (err) => new DependencyError("Error loading dependency", source, url, err));
}

async function toBuffer(stream: Readable): Promise<Buffer> {
  const chunks: Buffer[] = [];
  for await (const chunk of stream) {
    chunks.push(chunk);
  }
  return Buffer.concat(chunks);
}

class DependencyError extends Error {
  constructor(message: string, source?: string, dependency?: string | FileUrl | DataUrl | URL, cause?: Error | unknown) {
    super(message);
    this.name = "DependencyError";
    if (cause) {
      this.cause = cause;
    }
    if (dependency) {
      this.dependency = dependency;
    }
    if (source) {
      this.source = source;
    }
  }
  cause?: Error | unknown;
  dependency?: string | FileUrl | DataUrl | URL;
  source?: string;
}

class LocalDependencyNotFound extends Error {
  constructor(message: string, source?: string, pathOrUrl?: PathOrUrl, cause?: Error | unknown) {
    super(message);
    this.name = "LocalDependencyNotFound";
    if (cause) {
      this.cause = cause;
    }
    if (pathOrUrl) {
      this.pathOrUrl = pathOrUrl;
    }
    if (source) {
      this.source = source;
    }
  }

  cause?: Error | unknown;
  pathOrUrl?: PathOrUrl;
  source?: string;

}
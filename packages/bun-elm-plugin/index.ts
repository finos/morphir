import { type BunPlugin, type PluginBuilder } from "bun";
import { readFile, stat } from "node:fs/promises";
import { lookpath } from "find-bin";
import path from "node:path";
import { log, LogLevel } from "firan-logging";
import chalk from "chalk";
import * as elmCompiler from "node-elm-compiler";

// handler which does the logging to the console or anything
const logger = {
  [LogLevel.ERROR]: (tag, msg, params) =>
    console.error(
      `[${chalk.red("ERROR")}:${getTimestamp()}:${chalk.red(tag)}]`,
      msg,
      ...params
    ),
  [LogLevel.WARN]: (tag, msg, params) =>
    console.warn(
      `[${chalk.yellow("WARN")}:${getTimestamp()}:${chalk.yellow(tag)}]`,
      msg,
      ...params
    ),
  [LogLevel.INFO]: (tag, msg, params) =>
    console.log(
      `[${chalk.greenBright("INFO")}:${getTimestamp()}:${chalk.greenBright(tag)}]`,
      msg,
      ...params
    ),
  [LogLevel.TRACE]: (tag, msg, params) =>
    console.log(
      `[${chalk.cyan("TRACE")}:${getTimestamp()}:${chalk.cyan(tag)}]`,
      msg,
      ...params
    ),
  [LogLevel.DEBUG]: (tag, msg, params) =>
    console.log(
      `[${chalk.magenta("DEBUG")}:${getTimestamp()}:${chalk.magenta(tag)}]`,
      msg,
      ...params
    ),
} as Record<LogLevel, (tag: string, msg: unknown, params: unknown[]) => void>;

const namespace = "elm";
const PURE_FUNCS = [
  "F2",
  "F3",
  "F4",
  "F5",
  "F6",
  "F7",
  "F8",
  "F9",
  "A2",
  "A3",
  "A4",
  "A5",
  "A6",
  "A7",
  "A8",
  "A9",
];

export function ElmPlugin(config: ElmPluginConfig = DefaultConfig): BunPlugin {
  configureLogging(config.logging);

  return {
    name: "morphir-elm-plugin",
    async setup(builder: PluginBuilder) {
      log.info("Builder Info", builder);
      const isProd = process.env.NODE_ENV === "production";
      const defaultConfig = {
        optimize: isProd,
        cwd: process.cwd(),
        ...DefaultConfig,
      };
      const finalConfig = {
        ...defaultConfig,
        ...config,
      };

      const { optimize, cwd, debug, verbose, clearOnWatch } = finalConfig;
      const pathToElm = config.pathToElm || (await getPathToElm());
      log.debug("build", "Path to elm executable: ", pathToElm);
      const options = builder.config;
      if (options?.minify) {
        Object.assign(options, {
          pure: [...PURE_FUNCS], //[...(options.pure || []), ...PURE_FUNCS],
        });
      }

      const compileOptions = {
        pathToElm,
        optimize,
        processOpts: { stdout: "pipe" },
        cwd,
        debug,
        verbose,
      };
      const { cache, compileToStringSync } = cachedElmCompiler();

      const fileCache = new FileCache();

      const loadPaths = await getLoadPaths(cwd);

      log.debug("Load paths: ", loadPaths);

      // Register Onload callback
      builder.onLoad({ filter: /\.(elm)$/ }, async (args: any) => {
        log.trace("ElmPlugin.onLoad", args);

        const resolvedPath = args.path;

        // const resolvedPath = await resolvePath(
        //   cwd, //args?['resolveDir'] ,
        //   args.path,
        //   loadPaths
        // );

        log.debug("Resolved path: ", resolvedPath);

        const resolvedDependencies =
          await elmCompiler.findAllDependencies(resolvedPath);

        log.warn("build", "Resolved dependencies: ", resolvedDependencies);

        const text = await readFile(args.path, { encoding: "utf8" });
        //const exports = load(text) as Record<string, any>;
        const contents =
          "/*" +
          text +
          "*/const CLI = { init:(flags)=> ({...flags})}; export default CLI;";
        return {
          contents,
          loader: "js",
        };
      });

      builder.onResolve({ filter: /\.(elm)$/ }, (args) => {
        log.info("resolve", args);
          return {
            
        };
      });
    },
  };
}

function configureLogging(config: LoggingConfig = DefaultLoggingConfig) {
  log.init(config.levels, (level, tag, msg, params) => {
    logger[level as keyof typeof logger](tag, msg, params);
  });
}

function fileExists(file: string) {
  return stat(file)
    .then((stat) => stat.isFile())
    .catch((_) => false);
}

// Attempts to resolve a file path by joining to each load path, and returns the
// resolved path if that file exists.
// If no load paths are provided, or none resolve, the file path is assumed to
// be relative to `resolveDir`.
async function resolvePath(
  resolveDir: string,
  filePath: string,
  loadPaths: string[] = []
) {
  for (const loadPath of loadPaths) {
    const joinedPath = path.join(loadPath, filePath);

    if (await fileExists(joinedPath)) {
      return joinedPath;
    }
  }

  return path.join(resolveDir, filePath);
}

async function getLoadPaths(cwd: string = ".") {
  const file = await readFile(path.join(cwd, "elm.json"), "utf8");
  const elmPackage = JSON.parse(file);

  const paths: string[] =
    elmPackage["source-directories"].map((dir: string) => {
      return path.join(cwd, dir);
    }) || [];

  return paths;
}

async function getPathToElm() {
  //const commands = ['./node_modules/.bin/elm', 'elm'];
  const CMD_NOT_FOUND =
    "Could not find elm executable. Please ensure elm is installed and available in your PATH. You can install it using `bun add -D elm` or `npm install -D elm`.";

  //const foundCommands = await Promise.all(commands.map(lookpath));
  // const elmCommand = foundCommands.find((cmd) => cmd !== undefined);
  const elmCommand = await lookpath("elm", {
    include: ["./node_modules/.bin/"],
    includeCommonPaths: true,
  });
  if (elmCommand) {
    return elmCommand;
  } else {
    throw new Error(CMD_NOT_FOUND);
  }
}

function getTimestamp() {
  return new Date().toJSON();
}
function cachedElmCompiler() {
  const cache = new Map();

  const compileToStringSync = async (
    fileCache: FileCache,
    inputPath: string,
    compileOptions: any
  ) => {
    try {
      const output = await checkCache(
        fileCache,
        cache,
        inputPath,
        compileOptions
      );

      return output;
    } catch (e) {
      return { errors: [toBuildError(e)] };
    }
  };

  return { cache, compileToStringSync };
}

function toBuildError(error: any) {
  return { text: error.message };
}
// Cached version of `elmCompiler.compileToStringSync`
// Cache is persisted across builds
async function checkCache(
  fileCache: FileCache,
  cache: Cache,
  mainFilePath: any,
  compileOptions: any
) {
  const cached = cache.get(mainFilePath);
  const newInput = await readFileModificationTime(fileCache, mainFilePath);

  const depsUnchanged = await validateDependencies(
    fileCache,
    cached?.dependencies
  );

  if (depsUnchanged && cached?.input === newInput) {
    return cached.output;
  }
  // Can't use the async version:
  // https://github.com/phenax/esbuild-plugin-elm/issues/2
  const contents = elmCompiler.compileToStringSync(
    [mainFilePath],
    compileOptions
  );
  const output = { contents };

  cache.set(mainFilePath, {
    input: newInput,
    output,
    dependencies: cached?.dependencies,
  });

  return output;
}

// Cached version of `fs.stat`.
// Cache is cleared on each build.
async function readFileModificationTime(
  fileCache: FileCache,
  filePath: string
) {
  const cached = fileCache.get(filePath);

  if (cached !== undefined) {
    return cached;
  }
  const statsResult = await stat(filePath);
  const fileContents = statsResult.mtimeMs;

  fileCache.set(filePath, fileContents);

  return fileContents;
}

// Checks whether all deps for a "main" elm file are unchanged.
// These only include source deps (might need to reset the dev server if you add an extra dep).
// If not, we need to recompile the file importing them.
async function validateDependencies(
  fileCache: Map<string, any>,
  depsMap: Map<string, any>
) {
  const depStatus = await Promise.all(
    [...depsMap].map(async ([depPath, cachedDep]) => {
      const newInput = await readFileModificationTime(fileCache, depPath);

      if (cachedDep.input === newInput) {
        return true;
      }
      cachedDep.input = newInput;
      return false;
    })
  );

  return depStatus.every((isReady) => isReady);
}

export default ElmPlugin;

export interface ElmPluginConfig {
  optimize?: boolean;
  cwd?: string;
  debug?: boolean;
  clearOnWatch?: boolean;
  verbose?: boolean;
  pathToElm?: string;
  logging: LoggingConfig;
}

export interface LoggingConfig {
  levels: Record<string, LogLevel>;
}

export const DefaultLoggingConfig: LoggingConfig = {
  levels: {
    system: LogLevel.OFF,
    build: LogLevel.DEBUG,
  },
};

export const DefaultConfig: ElmPluginConfig = {
  verbose: false,
  logging: DefaultLoggingConfig,
};

interface Cache extends Map<string, CacheEntry> {}
class FileCache extends Map<string, FileCacheEntry> {}

type FileCacheEntry = number;

type CacheEntry = CacheEntryObject | string;

type CacheEntryObject = {
  input: any;
  output: any;
  dependencies: Dependencies;
};
interface Dependencies extends Map<string, Dependency> {}
type Dependency = any;

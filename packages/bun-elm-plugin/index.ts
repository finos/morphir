import { type BunPlugin } from "bun";
import Bun from "bun";
import fs from "node:fs/promises";
import path from "node:path";
import process from "node:process";
import { lookpath } from "find-bin";
import * as elmCompiler from "node-elm-compiler";
import { log, LogLevel } from "firan-logging";
import chalk from "chalk";

// handler which does the logging to the console or anything
const logger = {
  [LogLevel.ERROR]: (tag, msg, params) =>
    console.error(`[${chalk.red(tag)}]`, msg, ...params),
  [LogLevel.WARN]: (tag, msg, params) =>
    console.warn(`[${chalk.yellow(tag)}]`, msg, ...params),
  [LogLevel.INFO]: (tag, msg, params) =>
    console.log(`[${chalk.greenBright(tag)}]`, msg, ...params),
  [LogLevel.TRACE]: (tag, msg, params) =>
    console.log(`[${chalk.cyan(tag)}]`, msg, ...params),
  [LogLevel.DEBUG]: (tag, msg, params) =>
    console.log(`[${chalk.magenta(tag)}]`, msg, ...params),
} as Record<LogLevel, (tag: string, msg: unknown, params: unknown[]) => void>;

/**
 * initialize fran-logging
 * @param config JSON which assigns tags levels. An uninitialized,
 *    tag's level defaults to DEBUG.
 * @param callback? handle logging whichever way works best for you
 */
log.init(
  { transporter: "INFO", security: "ERROR", system: "OFF" },
  (level, tag, msg, params) => {
    logger[level as keyof typeof logger](tag, msg, params);
  }
);

const namespace = "elm";
const fileFilter = /\.elm$/;
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

const getPathToElm = async () => {
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
};

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
  const stat = await fs.stat(filePath);
  const fileContents = stat.mtimeMs;

  fileCache.set(filePath, fileContents);

  return fileContents;
}

function toBuildError(error: Error) {
  return { text: error.message };
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

// Recompute dependencies but keep cached artifacts if we had them
function updateDependencies(
  cache: Cache,
  resolvedPath: string,
  dependencyPaths: string[]
) {
  let cached = cache.get(resolvedPath) || {
    input: undefined,
    output: undefined,
    dependencies: new Map(),
  };

  const newValue = (depPath) =>
    cached.dependencies.get(depPath) || { input: undefined };
  const dependencies = new Map(
    dependencyPaths.map((depPath) => [depPath, newValue(depPath)])
  );

  cache.set(resolvedPath, {
    ...cached,
    dependencies,
  });
}

const cachedElmCompiler = () => {
  const cache = new Map();

  const compileToStringSync = async (fileCache, inputPath, compileOptions) => {
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
};

const fileExists = (file) => {
  return fs
    .stat(file)
    .then((stat) => stat.isFile())
    .catch((_) => false);
};

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
  const readFile = await fs.readFile(path.join(cwd, "elm.json"), "utf8");
  const elmPackage = JSON.parse(readFile);

  const paths: string[] =
    elmPackage["source-directories"].map((dir: string) => {
      return path.join(cwd, dir);
    }) || [];

  return paths;
}

export function ElmPlugin(config: ElmPluginConfig = {}): BunPlugin {
  return {
    name: "Elm Plugin",
    async setup(build: Bun.PluginBuilder) {
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

      log.debug("Build initial options: ", build.config);

      const options = build.config;
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

      //   build.onResolve({ filter: fileFilter }, async (args) => {
      //     const resolvedPath = await resolvePath(
      //       ".", //args?['resolveDir'] ,
      //       args.path,
      //       loadPaths
      //     );
      //     const resolvedDependencies =
      //       await elmCompiler.findAllDependencies(resolvedPath);

      //     // I think we need to update deps on each resolve because you might
      //     // change your imports on every build
      //     updateDependencies(cache, resolvedPath, resolvedDependencies);

      //     return {
      //       path: resolvedPath,
      //       namespace,
      //       watchFiles: [resolvedPath, ...resolvedDependencies],
      //     };
      //   });

      build.onLoad({ filter: fileFilter, namespace }, async (args) => {
        log.warn("system", `Compiling ${args.path}`);
        fileCache.clear();
        if (clearOnWatch) {
          // eslint-disable-next-line no-console
          console.clear();
        }

        const contents = await compileToStringSync(
          fileCache,
          args.path,
          compileOptions
        );

        const exports = {
          CLI: {
            init: (flags: any) => ({ flags: flags }),
          },
        };
        return {
          exports,
          loader: "object",
        };
      });
    },
  };
}

export default ElmPlugin;

interface Cache extends Map<string, CacheEntry> {}
class FileCache extends Map<string, FileCacheEntry> {}

type FileCacheEntry = number;

type CacheEntry = CacheEntryObject | string;

type CacheEntryObject = {
  input: any;
  output: any;
  dependencies: Dependencies;
};

export interface ElmPluginConfig {
  optimize?: boolean;
  cwd?: string;
  debug?: boolean;
  clearOnWatch?: boolean;
  verbose?: boolean;
  pathToElm?: string;
}

interface Dependencies extends Map<string, Dependency> {}
type Dependency = any;

export const DefaultConfig: ElmPluginConfig = {
  verbose: false,
};

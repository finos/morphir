import { type BunPlugin } from "bun";
import { readFile } from "node:fs/promises";
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

export function ElmPlugin(config: ElmPluginConfig = DefaultConfig): BunPlugin {
  configureLogging(config.logging);
  return {
    name: "morphir-elm-plugin",
    async setup(builder: any) {
      builder.onLoad({ filter: /\.(elm)$/ }, async (args: any) => {
        console.log("ElmPlugin.onLoad", args.path);
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
    },
  };
}

function configureLogging(config: LoggingConfig = DefaultLoggingConfig) {
  log.init(config.levels, (level, tag, msg, params) => {
    logger[level as keyof typeof logger](tag, msg, params);
  });
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

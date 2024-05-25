import Bun from "bun";
import ElmPlugin from "bun-elm-plugin";
import { type ElmPluginConfig } from "bun-elm-plugin";
import { log, LogLevel, tag } from "firan-logging";
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

const elmPluginConfig: ElmPluginConfig = {};

await Bun.build({
  entrypoints: ["src/morphir.ts", "src/lib.ts"],
  outdir: "dist",
  target: "node",
  plugins: [ElmPlugin()],
});

log.warn("build", "Build done.");

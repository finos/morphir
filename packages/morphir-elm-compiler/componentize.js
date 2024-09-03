import { log, LogLevel, tag } from "firan-logging";
import chalk from "chalk";
import { componentize } from "@bytecodealliance/componentize-js";
import {writeFile} from "node:fs/promises";

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
};

/**
 * initialize fran-logging
 * @param config JSON which assigns tags levels. An uninitialized,
 *    tag's level defaults to DEBUG.
 * @param callback? handle logging whichever way works best for you
 */
log.init(
  { transporter: "INFO", security: "ERROR", system: "OFF" },
  (level, tag, msg, params) => {
    logger[level](tag, msg, params);
  }
);

const { component } = await componentize(
  `
  export function hello (name) {
    return \`Hello \${name}\`;
  }
`,
  `
  package local:hello;
  world hello {
    export hello: func(name: string) -> string;
  }
`,
  {
    // recommended to get error debugging
    // disable to get a "pure component" without WASI imports
    enableStdout: true,
  }
);

const wasmFile = "dist/test.component.wasm";
await writeFile(wasmFile, component);

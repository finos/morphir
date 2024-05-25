import { type BunPlugin } from "bun";
import { readFileSync } from "fs";
import { log, LogLevel } from "firan-logging";
import chalk from "chalk";

export function ElmPlugin(config: ElmPluginConfig = DefaultConfig): BunPlugin {
  return {
    name: "morphir-elm-plugin",
    setup(builder: any) {
      builder.onLoad({ filter: /\.(elm)$/ }, (args: any) => {
        console.log("ElmPlugin.onLoad", args.path);
        const text = readFileSync(args.path, "utf8");
        //const exports = load(text) as Record<string, any>;
        const contents = "\\*" + text + "*/";
        return {
          contents,
          loader: "js",
        };
      });
    },
  };
}

export default ElmPlugin;

export interface ElmPluginConfig {
  optimize?: boolean;
  cwd?: string;
  debug?: boolean;
  clearOnWatch?: boolean;
  verbose?: boolean;
  pathToElm?: string;
}

export const DefaultConfig: ElmPluginConfig = {
  verbose: false,
};

#!/usr/bin/env node

// NPM Imports
import { Command } from "commander";
import * as fs from "fs";
import * as path from "path";
import * as util from "util";
import cli from "./cli";

// logging
require("log-timestamp");
const fsWriteFile = util.promisify(fs.writeFile);

export const command = new Command();
command
  .name("test-coverage")
  .description(
    "Generates report on number of branches in a Morphir value and TestCases covered"
  )
  .option(
    "-i, --ir <path>",
    "Source location where the Morphir IR will be loaded from.",
    "morphir-ir.json"
  )
  .option(
    "-t, --tests <path>",
    "Source location where the Morphir Test Json will be loaded from.",
    "morphir-tests.json"
  )
  .option(
    "-o, --output <path>",
    "Source location where the Morphir Test Coverage result will be ouput to.",
    "."
  )
  .action(run);

function run(options: { ir: string; tests: string; output: string }) {
  const { ir: irPath, tests: irTestPath, output: output } = options;
  return cli
    .testCoverage(irPath, irTestPath, output, options)
    .then((data) => {
      fsWriteFile(
        path.join(output, "morphir-test-coverage.json"),
        JSON.stringify(data)
      );
    })
    .catch((err) => {
      console.log("err --", err);
      process.exit(1);
    });
}

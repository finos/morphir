#!/usr/bin/env node

// NPM Imports
import { Command } from "commander";
import { dockerize } from "./cliAPI";

// logging
require("log-timestamp");

export const command = new Command();
command
  .name("dockerize")
  .description("Creates a Docker image of a Morphir IR with Morphir Develop")
  .option(
    "-p, --project-dir <path>",
    "Root directory of the project where morphir.json is located.",
    "."
  )
  .option("-f, --force", "Overwrite any Dockerfile in target location", false)
  .action(run);

function run(options: { projectDir: string; force: boolean }) {
  dockerize(options.projectDir, options);
}

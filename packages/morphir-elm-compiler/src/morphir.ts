#!/usr/bin/env node
// NPM imports
import { Command } from "commander";
import { readPackageUpSync } from "read-package-up";
import * as morphirMake from "./morphir-make";
import * as morphirStats from "./morphir-stats";
import * as morphirInit from "./morphir-init";

// Read the package.json of this package
const packageJson = readPackageUpSync()?.packageJson;

let version = packageJson?.version || "0.0.0";

// Set up Commander
const program = new Command();
program
  .version(version, "-v, --version")
  .addCommand(morphirMake.createCommand())
  .command("scala-gen", "Generate scala code from Morphir IR")
  .command("json-schema-gen", "Generate Json Schema from the Morphir IR")
  .command("snowpark-gen", "Generate Scala with Snowpark code from Morphir IR")
  .addCommand(morphirStats.command)
  .command(
    "dockerize",
    "Creates a docker image of a Morphir IR and Morphir Develop"
  )
  .command(
    "test-coverage",
    "Generates report on number of branches in a Morphir value and TestCases covered"
  )
  .command(
    "generate-test-data",
    "Creates a docker image of a Morphir IR and Morphir Develop"
  )
  .addCommand(morphirInit.command)
  .parse(process.argv);

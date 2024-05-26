#!/usr/bin/env node
// NPM imports
import { Command } from "commander";
import { readPackageUpSync } from "read-package-up";
import * as morphirDockerize from "./morphir-dockerize";
import * as morphirInit from "./morphir-init";
import * as morphirJsonSchemaGen from "./morphir-json-schema-gen";
import * as morphirMake from "./morphir-make";
import * as morphirScalaGen from "./morphir-scala-gen";
import * as morphirStats from "./morphir-stats";
import * as testCoverage from "./morphir-test-coverage";

// Read the package.json of this package
const packageJson = readPackageUpSync()?.packageJson;

let version = packageJson?.version || "0.0.0";

// Set up Commander
const program = new Command();
program
  .version(version, "-v, --version")
  .addCommand(morphirMake.createCommand())
  .addCommand(morphirScalaGen.command)
  .addCommand(morphirJsonSchemaGen.command)
  .command("snowpark-gen", "Generate Scala with Snowpark code from Morphir IR")
  .addCommand(morphirStats.command)
  .addCommand(morphirDockerize.command)
  .addCommand(testCoverage.command)
  .command(
    "generate-test-data",
    "Creates a docker image of a Morphir IR and Morphir Develop"
  )
  .addCommand(morphirInit.command)
  .parse(process.argv);

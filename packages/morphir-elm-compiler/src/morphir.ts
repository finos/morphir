#!/usr/bin/env node
// NPM imports
import { Command } from "commander";
import { readPackageUpSync } from "read-package-up";
import * as morphirDockerize from "./morphir-dockerize";
import * as morphirGenerateTestData from "./morphir-generate-test-data";
import * as morphirInit from "./morphir-init";
import * as morphirJsonSchemaGen from "./morphir-json-schema-gen";
import * as morphirMake from "./morphir-make";
import * as morphirScalaGen from "./morphir-scala-gen";
import * as morphirSnowparkGen from "./morphir-snowpark-gen";
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
  .addCommand(morphirSnowparkGen.command)
  .addCommand(morphirStats.command)
  .addCommand(morphirDockerize.command)
  .addCommand(testCoverage.command)
  .addCommand(morphirGenerateTestData.command)
  .addCommand(morphirInit.command)
  .parse(process.argv);

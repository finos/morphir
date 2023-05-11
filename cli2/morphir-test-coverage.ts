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

const program = new Command();
program
    .name("morphir test-coverage")
    .description("Generates report on number of branches in a Morphir value and TestCases covered")
    .option("-i, --ir <path>", "Source location where the Morphir IR will be loaded from.", "morphir-ir.json")
    .option("-t, --tests <path>", "Source location where the Morphir Test Json will be loaded from.", "morphir-tests.json")
    .option("-o, --output <path>", "Source location where the Morphir Test Coverage result will be ouput to.", ".")
    .parse(process.argv);

const { ir: irPath, tests: irTestPath, output: output } = program.opts();

cli.testCoverage(irPath, irTestPath, output, program.opts())
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

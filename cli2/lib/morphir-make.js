#!/usr/bin/env node
"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
// NPM imports
const commander_1 = require("commander");
const cliAPI_1 = require("./cliAPI");
// logging
require('log-timestamp');
// Set up Commander
const program = new commander_1.Command();
program
    .name('morphir make')
    .description('Translate Elm sources to Morphir IR')
    .option('-p, --project-dir <path>', 'Root directory of the project where morphir.json is located.', '.')
    .option('-o, --output <path>', 'Target file location where the Morphir IR will be saved.', 'morphir-ir.json')
    .option('-t, --types-only', 'Only include type information in the IR, no values.', false)
    .parse(process.argv);
const dirAndOutput = program.opts();
// run make
(0, cliAPI_1.make)(dirAndOutput.projectDir, dirAndOutput);

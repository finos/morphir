#!/usr/bin/env node
"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
// NPM Imports 
const commander_1 = require("commander");
const cliAPI_1 = require("./cliAPI");
// logging 
require('log-timestamp');
const program = new commander_1.Command();
program
    .name('morphir dockerize')
    .description('Creates a Docker image of a Morphir IR with Morphir Develop')
    .option('-p, --project-dir <path>', 'Root directory of the project where morphir.json is located.', '.')
    .option('-f, --force', 'Overwrite any Dockerfile in target location', false)
    .parse(process.argv);
// run 
(0, cliAPI_1.dockerize)(program.opts().projectDir, program.opts());

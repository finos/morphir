#!/usr/bin/env node
"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
// NPM imports
const path_1 = __importDefault(require("path"));
const commander_1 = require("commander");
// Read the package.json of this package
const packageJson = require(path_1.default.join(__dirname, '../../package.json'));
// Set up Commander
const program = new commander_1.Command();
program
    .version(packageJson.version, '-v, --version')
    .command('make', 'Translate Elm sources to Morphir IR')
    .command('scala-gen', 'Generate scala code from Morphir IR')
    .command('stats', 'Collect morphir features used in a model into a document')
    .command('dockerize', 'Creates a docker image of a Morphir IR and Morphir Develop')
    .parse(process.argv);

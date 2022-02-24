#!/usr/bin/env node
"use strict";
// 'use strict'
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
// NPM imports
// const path = require('path')
const path_1 = __importDefault(require("path"));
const commander_1 = require("commander");
// const commander = require('commander')
// Read the package.json of this package
const packageJson = require(path_1.default.join(__dirname, './../package.json'));
// Set up Commander
const program = new commander_1.Command();
program
    .version(packageJson.version, '-v, --version')
    .command('make', 'Translate Elm sources to Morphir IR')
    .command('gen', 'Generate code from Morphir IR')
    .command('develop', 'Start up a web server and expose developer tools through a web UI')
    .command('test', 'Start Testing all the test cases present in morphir-ir.json')
    .parse(process.argv);

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
const packageJson = require(path_1.default.join(__dirname, './../package.json'));
// Set up Commander
const program = new commander_1.Command();
program
    .version(packageJson.version, '-v, --version')
    .command('elm', 'Invoke Elm tooling')
    .command('dapr', 'Invoke Dapr tooling')
    .parse(process.argv);

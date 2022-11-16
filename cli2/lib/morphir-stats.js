#!/usr/bin/env node
"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
// NPM imports
const commander_1 = require("commander");
const cli_1 = __importDefault(require("./cli"));
// logging
require('log-timestamp');
// Set up Commander
const program = new commander_1.Command();
program
    .name('morphir stats')
    .description('Collect morphir features used in a model into a document')
    .option('-i, --input <path>', 'Source location where the Morphir IR will be loaded from.', 'morphir-ir.json')
    .option('-o, --output <path>', 'Target location where the generated code will be saved.', './stats')
    .parse(process.argv);
const { input: inputPath, output: outputPath } = program.opts();
cli_1.default.stats(inputPath, outputPath, program.opts())
    .then(() => {
    console.log('Done');
})
    .catch(err => {
    console.log(err);
    process.exit(1);
});

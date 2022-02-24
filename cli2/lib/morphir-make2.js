#!/usr/bin/env node
"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
// NPM imports
const commander_1 = require("commander");
const cli = require("./cli");
// logging
require('log-timestamp');
console.log("ts workings");
// Set up Commander
const program = new commander_1.Command();
program
    .name('morphir-make')
    .description('Translate Elm sources to Morphir IR')
    .option('-p, --project-dir <path>', 'Root directory of the project where morphir.json is located.', '.')
    .option('-o, --output <path>', 'Target file location where the Morphir IR will be saved.', 'morphir-ir.json')
    .option('-t, --types-only', 'Only include type information in the IR, no values.', false)
    .parse(process.argv);
const dirAndOutput = program.opts();
cli.make(dirAndOutput.projectDir, program.opts())
    .then((packageDef) => {
    console.log(`Writing file ${dirAndOutput.output}.`);
    cli.writeFile(dirAndOutput.output, JSON.stringify(packageDef, null, 4))
        .then(() => {
        console.log('Done.');
    })
        .catch((err) => {
        console.error(`Could not write file: ${err}`);
    });
})
    .catch((err) => {
    if (err.code == 'ENOENT') {
        console.error(`Could not find file at '${err.path}'`);
    }
    else {
        if (err instanceof Error) {
            console.error(err);
        }
        else {
            console.error(`Error: ${JSON.stringify(err, null, 2)}`);
        }
    }
    process.exit(1);
});

#!/usr/bin/env node

// NPM imports
import { Command } from 'commander';
import path from 'path';

import cli from './cli';

require('log-timestamp')

const program = new Command
program
    .name('morphir json-schema-gen')
    .description('Generate Json Schema from Morphir IR')
    .option('-i, --input <path>', 'Source location where the Morphir IR will be loaded from.', 'morphir-ir.json')
    .option('-o, --output <path>', 'Target location where the generated code will be saved.', './dist')
    .option('-t, --target <type>', 'Language to Generate. It would always be JsonSchema', 'JsonSchema')
    .option('-e, --target-version <version>', 'Language version to Generate.', '2.11')
    .option('-c, --copy-deps', 'Copy the dependencies used by the generated code to the output path.', false)
    .option('-f, --filename <filename>', 'Filename of the generated JSON Schema.', '')
    .option('-m, --limit-to-modules <comma.separated,list.of,module.names>', 'Limit the set of modules that will be included.', '')
    .option('-cc, --custom-config <filepath>', 'A filepath to load additional configuration for the backend.')
    .parse(process.argv)

cli.gen(program.opts().input, path.resolve(program.opts().output), program.opts())
    .then(() => {
        console.log("Done")
    })
    .catch((err) => {
        console.log(err);
        process.exit(1)
    })


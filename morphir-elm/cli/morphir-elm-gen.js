#!/usr/bin/env node
'use strict'

// NPM imports
const path = require('path')
const commander = require('commander')
const cli = require('./cli')

//logging
require('log-timestamp')

// Set up Commander
const program = new commander.Command()
program
    .name('morphir-elm gen')
    .description('Generate code from Morphir IR')
    .option('-i, --input <path>', 'Source location where the Morphir IR will be loaded from.', 'morphir-ir.json')
    .option('-o, --output <path>', 'Target location where the generated code will be saved.', './dist')
    .option('-t, --target <type>', 'Language to Generate (Scala | SpringBoot | cypher | triples | TypeScript).', 'Scala')
    .option('-e, --target-version <version>', 'Language version to Generate.', '2.11')
    .option('-c, --copy-deps', 'Copy the dependencies used by the generated code to the output path.', false)
    .option('-m, --modules-to-include <comma.separated,list.of,module.names>', 'Limit the set of modules that will be included.')
    .option('-s, --include-codecs', 'Generate JSON codecs', false)
    .option('-f, --filename <filename>', 'Filename of the generated JSON Schema.', '')
    .option('-ls, --include <comma.separated,list.of,strings>', 'Limit what will be included.', '')
    .option('-dec, --decorations <filename>', 'JSON file with decorations')
    .parse(process.argv)

cli.gen(program.opts().input, path.resolve(program.opts().output), program.opts())
    .then(() => {
        console.log("Done.")
    })
    .catch((err) => {
        console.error(err)
        process.exit(1)
    })


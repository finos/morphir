#!/usr/bin/env node

//NPM imports
import path from 'path';
import {Command} from 'commander'
import cli = require('./cli')

require('log-timestamp')

const program = new Command()
program
    .name('morphir scala-gen')
    .description('Generate scala code from Morphir IR')
    .option('-i, --input <path>', 'Source location where the Morphir IR will be loaded from.', 'morphir-ir.json')
    .option('-o, --output <path>', 'Target location where the generated code will be saved.', './dist')
    .option('-t, --target <type>', 'Language to Generate.', 'Scala')
    .option('-e, --target-version <version>', 'Language version to Generate.', '2.11')
    .option('-c, --copy-deps', 'Copy the dependencies used by the generated code to the output path.', false)
    .option('-m, --modules-to-include <comma.separated,list.of,module.names>', 'Limit the set of modules that will be included.')
    .parse(process.argv)

cli.gen(program.opts().input, path.resolve(program.opts().output), program.opts())
    .then(() =>{
        console.log("Done")
    })
    .catch((err) =>{
        console.log(err)
        process.exit(1)
    })

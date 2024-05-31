#!/usr/bin/env node
'use strict'


// NPM imports
const commander = require('commander')


// logging
require('log-timestamp')

// Set up Commander
const program = new commander.Command()
program
    .name('morphir-elm make')
    .description('Translate Elm sources to Morphir IR')
    .option('-p, --project-dir <path>', 'Root directory of the project where morphir.json is located.', '.')
    .option('-o, --output <path>', 'Target file location where the Morphir IR will be saved.', 'morphir-ir.json')
    .option('-t, --types-only', 'Only include type information in the IR, no values.', false)
    .option('-f, --fallback-cli', 'Use old cli make function.', false)
    .option('-i, --indent-json', 'Use indentation in the generated JSON file.', false)
    .parse(process.argv)

const programOptions = program.opts()

// running function
runAppropriateCli(programOptions.projectDir, programOptions)

// runs cli1 if flag passed, else cli2
function runAppropriateCli(projectDir, opts) {
    if (opts.fallbackCli) {
        make(projectDir, opts)
    }

    else {
        const cli2 = require('../cli2/lib/cliAPI')
        cli2.make(projectDir, opts)
    }
}

function make(projectDir, opts) {
    const cli = require('./cli')

    cli.make(projectDir, opts)
        .then((packageDef) => {
            console.log(`Writing file ${opts.output}.`)
            cli.writeFile(opts.output, JSON.stringify(packageDef, null, opts.indentJson ? 4 : 0))
                .then(() => {
                    console.log('Done.')
                })
                .catch((err) => {
                    console.error(`Could not write file: ${err}`)
                })
        })
        .catch((err) => {
            if (err.code == 'ENOENT') {
                console.error(`Could not find file at '${err.path}'`)
            } else {
                if (err instanceof Error) {
                    console.error(err)
                } else {
                    console.error(`Error: ${JSON.stringify(err, null, 2)}`)
                }
            }
            process.exit(1)
        })
}
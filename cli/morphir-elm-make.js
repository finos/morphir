#!/usr/bin/env node
'use strict'

// NPM imports
const commander = require('commander')
const cli = require('./cli')

// Set up Commander
const program = new commander.Command()
program
    .name('morphir-elm make')
    .description('Translate Elm sources to Morphir IR')
    .option('-p, --project-dir <path>', 'Root directory of the project where morphir.json is located.', '.')
    .option('-o, --output <path>', 'Target file location where the Morphir IR will be saved.', 'morphir-ir.json')
    .parse(process.argv)


cli.make(program.projectDir)
    .then((packageDef) => {
        console.log(`Writing file ${program.output}.`)
        cli.writeFile(program.output, JSON.stringify(packageDef, null, 4))
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

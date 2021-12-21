#!/usr/bin/env node
'use strict'

// NPM imports
const path = require('path')
const commander = require('commander')

// Read the package.json of this package
const packageJson = require(path.join(__dirname, '../package.json'))

// Set up Commander
const program = new commander.Command()
program
    .version(packageJson.version, '-v, --version')
    .command('make', 'Translate Elm sources to Morphir IR')
    .command('gen', 'Generate code from Morphir IR')
    .command('develop', 'Start up a web server and expose developer tools through a web UI')
    .command('test','Start Testing all the test cases present in morphir-ir.json')
    .parse(process.argv)

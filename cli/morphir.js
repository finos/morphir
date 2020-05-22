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
    .command('elm', 'Invoke Elm tooling')
    .command('dapr', 'Invoke Dapr tooling')
    .parse(process.argv)
#!/usr/bin/env node
// NPM imports
import path from 'path'
import {Command} from 'commander'

// Read the package.json of this package
const packageJson = require(path.join(__dirname, './../package.json'))

// Set up Commander
const program = new Command()
program
    .version(packageJson.version, '-v, --version')
    .command('elm', 'Invoke Elm tooling')
    .command('dapr', 'Invoke Dapr tooling')
    .parse(process.argv)
#!/usr/bin/env node
// 'use strict'

// NPM imports
// const path = require('path')
import path from 'path'
import {Command} from 'commander'
// const commander = require('commander')

// Read the package.json of this package
const packageJson = require(path.join(__dirname, './package.json'))

// Set up Commander
const program = new Command()
program
    .version(packageJson.version, '-v, --version')
    .command('make', 'Translate Elm sources to Morphir IR')
    .parse(process.argv)

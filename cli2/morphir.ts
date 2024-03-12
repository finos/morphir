#!/usr/bin/env node
// NPM imports
import path from 'path'
import {Command} from 'commander'

// Read the package.json of this package
const packageJson = require(path.join(__dirname, '../../package.json'))

// Set up Commander
const program = new Command()
program
    .version(packageJson.version, '-v, --version')
    .command('make', 'Translate Elm sources to Morphir IR')
    .command('scala-gen', 'Generate scala code from Morphir IR')
    .command('json-schema-gen', 'Generate Json Schema from the Morphir IR')
    .command('snowpark-gen','Generate Scala with Snowpark code from Morphir IR')
    .command('stats', 'Collect morphir features used in a model into a document')
    .command('dockerize', 'Creates a docker image of a Morphir IR and Morphir Develop')
    .command('test-coverage', 'Generates report on number of branches in a Morphir value and TestCases covered')
    .command('generate-test-data', 'Creates a docker image of a Morphir IR and Morphir Develop')
    .command('init', 'Launches an interactive session to initialize a new morphir project.')
    .parse(process.argv)
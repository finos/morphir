#!/usr/bin/env node

// NPM imports
import { Command } from 'commander'

import * as fs from 'fs'
import * as util from 'util'
import * as path from 'path'

const fsExists = util.promisify(fs.exists)
const fsWriteFile = util.promisify(fs.writeFile)
const fsMakeDir = util.promisify(fs.mkdir)
const fsReadFile = util.promisify(fs.readFile)
const readdir = util.promisify(fs.readdir)

const worker = require('./../Morphir.Elm.Generator').Elm.Morphir.Elm.Generator.init()

// logging
require('log-timestamp')

// Set up Commander
const program = new Command()
program
	.name('morphir generate-test-data')
	.description('Generate test data for Models (types) in a Morphir IR')
	.option('-p, --project-dir <path>', 'Root directory of the project where morphir.json is located.', '.')
	.option('-o, --output <path>', 'Target file location where the test data will be saved.', 'test-data.json')
	.option('--seed <seed>', 'seed to use for randomness', Date.now().toString())
	.option('--size <size>', 'size of the data to be generated for each target', '1')
	.option('--targets <typefqns...>', 'Fully qualified names of types you want to generate test data for.')
	.option(
		'--config <path-to-config>',
		'specify a json file where configuration can be read from. Overrides other command options.'
	)
	.parse(process.argv)

interface GenerationOptions {
	morphirIrJson: any
	targets: [string]
	seed: number
	size: number
}

// run data generation
async function generateData() {
	const programOptions = program.opts()

	// CREATE CONFIG OPTIONS
	const morphirJsonPath: string = path.join(programOptions.projectDir, 'morphir-ir.json')
	if (!(await fsExists(morphirJsonPath))) throw Error('Not a morphir directory')
	const distroData = (await fsReadFile(morphirJsonPath)).toString()
	const distroJson = JSON.parse(distroData)

	if (!programOptions.targets || programOptions.targets.length <= 0) throw 'targets not provided'

	const opts: GenerationOptions = {
		morphirIrJson: distroJson,
		targets: programOptions.targets,
		seed: parseInt(programOptions.seed),
		size: parseInt(programOptions.size)
	}

	// SEND OFF TO ELM

	worker.ports.decodeFailed.subscribe((err: any) => {
		console.log('Decode Failed')
		console.log(err)
	})

	worker.ports.generationFailed.subscribe((err: any) => {
		console.log('Generation Failed', err)
		console.log(err)
	})

	worker.ports.generated.subscribe((data: any) => {
		const dataString: string = JSON.stringify(data, null, 4)
		const outputPath: string = path.join(programOptions.projectDir, programOptions.output)

		console.log('Writing test data to ' + outputPath)
		fsWriteFile(outputPath, dataString)
			.then(() => console.log('Done.'))
			.catch(err => {
				console.log(err)
			})
	})

	console.log('starting test data generation with options', opts)

	worker.ports.generate.send(opts)
}

generateData()

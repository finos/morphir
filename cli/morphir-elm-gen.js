#!/usr/bin/env node
'use strict'

// NPM imports
const path = require('path')
const util = require('util')
const fs = require('fs')
const readdir = util.promisify(fs.readdir)
const lstat = util.promisify(fs.lstat)
const readFile = util.promisify(fs.readFile)
const writeFile = util.promisify(fs.writeFile)
const commander = require('commander')

// Elm imports
const worker = require('./Morphir.Elm.GenCLI').Elm.Morphir.Elm.GenCLI.init()

// Set up Commander
const program = new commander.Command()
program
    .name('morphir-elm gen')
    .description('Translate Elm sources to a Dapr sources')
    .option('-p, --project-dir <path>', 'Root directory of the project where morphir.json is located.', '.')
    .option('-o, --output <path>', 'Target location where the Dapr sources will be sent. Defaults to STDOUT.')
    .parse(process.argv)


gen(program.projectDir, program.output)
    .then(result => {
        if (program.output) {
            console.log('Done.')
        }
    })
    .catch((err) => {
        if (err.code == 'ENOENT') {
            console.error(`Could not find file at '${err.path}'`)
        } else {
            console.error(err)
        }
        process.exit(1)
    })

async function gen(projectDir, output) {
    const morphirJsonPath = path.join(projectDir, 'morphir-tests.json')
    const morphirJsonContent = await readFile(morphirJsonPath)
    const morphirJson = JSON.parse(morphirJsonContent.toString())
    const sourceFiles = await readElmSources(morphirJson.sourceDirectory)
    const result = await packageDefAndDaprCodeFromSrc(morphirJson, sourceFiles)
    if (output) {
        console.log(`Writing file ${output}.`)
        await writeFile(output, JSON.stringify(result, null, 4))
    } else {
        console.log(JSON.stringify(result))
    }
    return result
}

async function packageDefAndDaprCodeFromSrc(morphirJson, sourceFiles) {
    return new Promise((resolve, reject) => {
        worker.ports.decodeError.subscribe(err => {
            reject(err)
        })

        worker.ports.packageDefAndDaprCodeFromSrcResult.subscribe(([err, ok]) => {
            if (err) {
                reject(err)
            } else {
                resolve(ok)
            }
        })

        worker.ports.packageDefinitionFromSource.send([morphirJson, sourceFiles])
    })
}

async function readElmSources(dir) {
    const readElmSource = async function (filePath) {
        const content = await readFile(filePath)
        return {
            path: filePath,
            content: content.toString()
        }
    }
    const readDir = async function (currentDir) {
        const entries = await readdir(currentDir, { withFileTypes: true })
        const elmSources =
            entries
                .filter(entry => entry.isFile() && entry.name.endsWith('.elm'))
                .map(entry => readElmSource(path.join(currentDir, entry.name)))
        const subDirSources =
            entries
                .filter(entry => entry.isDirectory())
                .map(entry => readDir(path.join(currentDir, entry.name)))
                .reduce(async (soFarPromise, nextPromise) => {
                    const soFar = await soFarPromise
                    const next = await nextPromise
                    return soFar.concat(next)
                }, Promise.resolve([]))
        return elmSources.concat(await subDirSources)
    }

    return Promise.all(await readDir(dir))
}
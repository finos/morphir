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
const worker = require('./Morphir.Elm.CLI').Elm.Morphir.Elm.CLI.init()

// Set up Commander
const program = new commander.Command()
program
    .name('morphir-elm make')
    .description('Translate Elm sources to Morphir IR')
    .option('-p, --project-dir <path>', 'Root directory of the project where morphir.json is located.', '.')
    .option('-o, --output <path>', 'Target location where the Morphir IR will be sent. Defaults to STDOUT.')
    .parse(process.argv)


make(program.projectDir, program.output)
    .then((packageDef) => {
        if (program.output) {
            console.log('Done.')
        }
    })
    .catch((err) => {
        if (err.code == 'ENOENT') {
            console.error(`Could not find file at '${err.path}'`)
        } else {
            console.error(JSON.stringify(err))
        }
        process.exit(1)
    })

async function make(projectDir, output) {
    const morphirJsonPath = path.join(projectDir, 'morphir.json')
    const morphirJsonContent = await readFile(morphirJsonPath)
    const morphirJson = JSON.parse(morphirJsonContent.toString())
    const sourceFiles = await readElmSources(path.join(projectDir, morphirJson.sourceDirectory))
    const packageDef = await packageDefinitionFromSource(morphirJson, sourceFiles)
    if (output) {
        console.log(`Writing file ${output}.`)
        await writeFile(output, JSON.stringify(packageDef, null, 4))
    } else {
        console.log(JSON.stringify(packageDef))
    }
    return packageDef
}

async function packageDefinitionFromSource(morphirJson, sourceFiles) {
    return new Promise((resolve, reject) => {
        worker.ports.decodeError.subscribe(err => {
            reject(err)
        })

        worker.ports.packageDefinitionFromSourceResult.subscribe(([err, ok]) => {
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
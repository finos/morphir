#!/usr/bin/env node
'use strict'

// NPM imports
const path = require('path')
const util = require('util')
const fs = require('fs')
const readdir = util.promisify(fs.readdir)
const readFile = util.promisify(fs.readFile)
const commander = require('commander')

// Elm imports
const worker = require('./Morphir.Elm.EncodersCLI').Elm.Morphir.Elm.EncodersCLI.init()

// Set up Commander
const program = new commander.Command()
program
    .name('morphir-elm gen')
    .description('Generate code from Morphir IR')
    .parse(process.argv)


worker.ports.elmEncoderBackend.subscribe(res => {
    console.log(res)
})


const packageInfo = {
    name: "morphir",
    exposedModules: ["A"]
}


const testDir = "tests/Morphir/Elm/Backend/Codec/Tests"

readElmSources(testDir)
    .then((sourceFiles) => {
        console.log("Generating elm encoders for following:")
        sourceFiles.forEach(element => {
            console.log(element.path)
        });
        console.log("")
        worker.ports.elmFrontEnd.send([packageInfo, sourceFiles])
        console.log("")
    })



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
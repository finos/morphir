#!/usr/bin/env node
'use strict'

// NPM imports
const path = require('path')
const util = require('util')
const fs = require('fs')
const getStdin = require('get-stdin')
const readdir = util.promisify(fs.readdir)
const mkdir = util.promisify(fs.mkdir)
const lstat = util.promisify(fs.lstat)
const readFile = util.promisify(fs.readFile)
const writeFile = util.promisify(fs.writeFile)
const unlink = util.promisify(fs.unlink)
const commander = require('commander')

// Elm imports
const worker = require('./Morphir.Elm.CLI').Elm.Morphir.Elm.CLI.init()

// Set up Commander
const program = new commander.Command()
program
    .name('morphir-elm gen')
    .description('Generate code from Morphir IR')
    .option('-i, --input <path>', 'Source location where the Morphir IR will be loaded from. Defaults to STDIN.')
    .option('-o, --output <path>', 'Target location where the generated code will be saved. Defaults to ./dist.', './dist')
    .parse(process.argv)


gen(program.input, path.resolve(program.output), {})
    .then(() => {
        console.log("Done.")
    })
    .catch((err) => {
        console.error(err)
        process.exit(1)
    })

async function gen(input, outputPath, options) {
    const morphirIrJson = input ? await readFile(path.resolve(input)) : await getStdin()
    const fileMap = await generate(options, JSON.parse(morphirIrJson.toString()))
    const writePromises =
        fileMap.map(async ([[dirPath, fileName], content]) => {
            const fileDir = dirPath.reduce((accum, next) => path.join(accum, next), outputPath)
            const filePath = path.join(fileDir, fileName)
            if (await fileExist(filePath)) {
                console.log(`UPDATE - ${filePath}`)
            } else {
                await mkdir(fileDir, { recursive: true })
                console.log(`INSERT - ${filePath}`)
            }
            return writeFile(filePath, content)
        })
    const filesToDelete = await findFilesToDelete(outputPath, fileMap)
    const deletePromises =
        filesToDelete.map(async (fileToDelete) => {
            console.log(`DELETE - ${fileToDelete}`)
            return await unlink(fileToDelete)
        })
    return Promise.all(writePromises.concat(deletePromises))
}

async function generate(options, ir) {
    return new Promise((resolve, reject) => {
        worker.ports.decodeError.subscribe(err => {
            reject(err)
        })

        worker.ports.generateResult.subscribe(([err, ok]) => {
            if (err) {
                reject(err)
            } else {
                resolve(ok)
            }
        })

        worker.ports.generate.send([options, ir])
    })
}

async function fileExist(filePath) {
    return new Promise((resolve, reject) => {
        fs.access(filePath, fs.F_OK, (err) => {
            if (err) {
                resolve(false)
            } else {
                resolve(true)
            }
        })
    });
}

async function findFilesToDelete(outputPath, fileMap) {
    const readDir = async function (currentDir, generatedFiles) {
        const entries = await readdir(currentDir, { withFileTypes: true })
        const filesToDelete =
            entries
                .filter(entry => {
                    const entryPath = path.join(currentDir, entry.name)
                    return entry.isFile() && !generatedFiles.includes(entryPath)
                })
                .map(entry => path.join(currentDir, entry.name))
        const subDirFilesToDelete =
            entries
                .filter(entry => entry.isDirectory())
                .map(entry => readDir(path.join(currentDir, entry.name), generatedFiles))
                .reduce(async (soFarPromise, nextPromise) => {
                    const soFar = await soFarPromise
                    const next = await nextPromise
                    return soFar.concat(next)
                }, Promise.resolve([]))
        return filesToDelete.concat(await subDirFilesToDelete)
    }

    const files =
        fileMap.map(([[dirPath, fileName], content]) => {
            const fileDir = dirPath.reduce((accum, next) => path.join(accum, next), outputPath)
            return path.resolve(fileDir, fileName)
        })
    return Promise.all(await readDir(outputPath, files))
}
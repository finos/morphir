'use strict'

// NPM imports
const path = require('path')
const util = require('util')
const fs = require('fs')
const readdir = util.promisify(fs.readdir)
const mkdir = util.promisify(fs.mkdir)
const readFile = util.promisify(fs.readFile)
const fsWriteFile = util.promisify(fs.writeFile)
const outputPath = "../src/Morphir/IR/SDK/SDKNativeFunctions.elm"
// Elm imports
const worker = require('./Morphir.Elm.DevCLI').Elm.Morphir.Elm.DevCLI.init()


worker.ports.respond.subscribe(async result => {
    await fsWriteFile(outputPath , result )
})
worker.ports.request.send("Generate all SDK native functions")


const commander = require('commander')
const program = new commander.Command()
program
    .command('gen-sdk-native <output-dir>')
    .description('Generate all SDK native functions')
    .action((outputDir) => {
        console.log(program)
        worker.ports.request.send("gen-sdk-native")
    })

program.parse(process.argv)

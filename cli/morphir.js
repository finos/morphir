'use strict'
const util = require('util')
const path = require('path')
const fs = require('fs')
const readdir = util.promisify(fs.readdir)
const worker = require('./Morphir.Elm.CLI').Elm.Morphir.Elm.CLI.init()


worker.ports.decodeError.subscribe(res => {
    console.error(res)
})

worker.ports.packageDefinitionFromSourceResult.subscribe(res => {
    console.log(JSON.stringify(res))
})


const packageInfo = {
    name: "morphir",
    exposedModules: ["A"]
}


const sourceDir = "../src"

const sourceFiles = [
    { path: "A.elm"
    , content: "module A exposing (..)"
    }
]

worker.ports.packageDefinitionFromSource.send([packageInfo, sourceFiles])


async function readSourceFiles(rootDir) {
    const entries = await readdir(rootDir, {withFileTypes: true})
    const sourceFiles = 
        entries
            .filter(dirent => dirent.isFile() && dirent.name.endsWith('.elm'))
            .map(dirent => {
                path: path.resolve(rootDir, dirent.name)
            })
    const childSourceFiles = await Promise.all(
        entries
            .filter(dirent => dirent.isDirectory())
            .map(dirent => readSourceFiles(path.resolve(rootDir, dirent.name)))
    )    
    childSourceFiles.reduce((a, b) => a.concat(b))
}
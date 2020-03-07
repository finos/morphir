'use strict'
const path = require('path')
const util = require('util')
const fs = require('fs')
const readdir = util.promisify(fs.readdir)
const readFile = util.promisify(fs.readFile)
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

readElmSources(sourceDir)
.then((sourceFiles) => {
    worker.ports.packageDefinitionFromSource.send([packageInfo, sourceFiles])
    sourceFiles.forEach(element => {
        console.log(element.path)
    });
})
.catch((err) => {
    console.error(err)
})



async function readElmSources(dir) {
    const readElmSource = async function(filePath) {
        const content = await readFile(filePath) 
        return {
            path: filePath,
            content: content.toString()
        }
    }
    const readDir = async function(currentDir) {
        const entries = await readdir(currentDir, {withFileTypes: true})
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
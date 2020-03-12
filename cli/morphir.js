'use strict'
const path = require('path')
const util = require('util')
const fs = require('fs')
const readdir = util.promisify(fs.readdir)
const readFile = util.promisify(fs.readFile)
const packageDefWorker = require('./Morphir.Elm.CLI').Elm.Morphir.Elm.CLI.init()
const elmCodecWorker = require('./Morphir.Elm.CodecsCLI').Elm.Morphir.Elm.CodecsCLI.init()


packageDefWorker.ports.decodeError.subscribe(res => {
    console.error(res)
})

packageDefWorker.ports.packageDefinitionFromSourceResult.subscribe(res => {
    console.log(JSON.stringify(res))
})

elmCodecWorker.ports.elmEncoderBackend.subscribe(res => {
    console.log(res)
})


const packageInfo = {
    name: "morphir",
    exposedModules: ["A"]
}


const sourceDir = "../src"
const testDir = "../tests/Morphir/Codec/Tests"

readElmSources(sourceDir)
.then((sourceFiles) => {
    packageDefWorker.ports.packageDefinitionFromSource.send([packageInfo, sourceFiles])
    sourceFiles.forEach(element => {
        console.log(element.path)
    });
})
.catch((err) => {
    console.error(err)
})

readElmSources(testDir)
.then((sourceFiles) => {
    console.log ("Generating elm codecs for following:")
    sourceFiles.forEach(element => {
        console.log(element.path)
    });
    console.log ("")
    elmCodecWorker.ports.elmFrontEnd.send([packageInfo, sourceFiles])
    console.log ("")
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
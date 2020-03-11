'use strict'
// NPM imports
const path = require('path')
const util = require('util')
const fs = require('fs')
const readdir = util.promisify(fs.readdir)
const readFile = util.promisify(fs.readFile)
const commander = require('commander')

// Elm imports
const packageDefWorker = require('./Morphir.Elm.CLI').Elm.Morphir.Elm.CLI.init()
const elmEncoderWorker = require('./Morphir.Elm.EncodersCLI').Elm.Morphir.Elm.EncodersCLI.init()

// Read the package.json of this package
const packageJson = require(path.join(__dirname, '../package.json'))

// Set up Commander
const program = new commander.Command()
program
    .version(packageJson.version, '-v, --version')
    .parse(process.argv)


packageDefWorker.ports.decodeError.subscribe(res => {
    console.error(res)
})

packageDefWorker.ports.packageDefinitionFromSourceResult.subscribe(res => {
    console.log(JSON.stringify(res))
})

elmEncoderWorker.ports.elmEncoderBackend.subscribe(res => {
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
        console.log("Generating elm encoders for following:")
        sourceFiles.forEach(element => {
            console.log(element.path)
        });
        console.log("")
        elmEncoderWorker.ports.elmFrontEnd.send([packageInfo, sourceFiles])
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
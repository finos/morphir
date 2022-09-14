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
const childProc = require('child_process')
const fsExtra = require('fs-extra')

// Elm imports
const worker = require('./Morphir.Elm.DaprCLI').Elm.Morphir.Elm.DaprCLI.init()

// Set up Commander
const program = new commander.Command()
program
    .name('morphir-dapr ')
    .description('Generate Dapr Application from Morphir Model')
    .option('-p, --project-dir <path>', 'Root directory of the project where morphir-dapr.json is located.', '.')
    .option('-o, --output <path>', 'Target location where the Dapr sources will be sent. Will create it if it does not exist', 'dapr-output')
    .option('-i, --info', 'Print dapr intermediate output (elm) to STDOUT.')
    .option('-d, --delete', 'Delete build directory')
    .parse(process.argv)


gen(program.opts().projectDir, program.opts().output, program.opts().debug, program.opts().delete)
    .then(result => {
        console.log('Done!')
    })
    .catch((err) => {
        if (err.code == 'ENOENT') {
            console.error(`Could not find file at '${err.path}'`)
        } else {
            console.error(err)
        }
        process.exit(1)
    })

async function gen(projectDir, output, debug, deleteBuildDir) {
    const morphirJsonPath = path.join(projectDir, 'morphir-dapr.json') // nosemgrep : path-join-resolve-traversal
    const morphirJsonContent = await readFile(morphirJsonPath)
    const morphirJson = JSON.parse(morphirJsonContent.toString())
    const sourceFiles = await readElmSources(morphirJson.sourceDirectories)
    const result = await packageDefAndDaprCodeFromSrc(morphirJson, sourceFiles)

    if (debug) {
        console.log(JSON.stringify(result.elmBackendResult))
    }

    const buildDir = 'dapr-stuff'

    console.log(`Clearing ${buildDir} ...`)
    fs.rmdirSync(buildDir, { recursive: true })

    console.log(`Creating build directory: ${buildDir}`)
    fs.mkdirSync(buildDir)

    console.log(`Writing dapr files to ${buildDir} ...`)
    await writeFile(`${buildDir}/Main.elm`, result.elmBackendResult)

    console.log(`Copying compilation assets to ${buildDir} ...`)
    fsExtra.copySync(`${__dirname}/assets/`, buildDir)
    fsExtra.copySync(`${__dirname}/../src`, buildDir)

    console.log(`Copying original sources to ${buildDir}`)
    morphirJson
        .sourceDirectories
        .map(async function (dir) {
            fsExtra.copySync(dir.toString(), buildDir)
        })

    console.log(`Using local elm-platform to perform final compilation`)
    childProc.execSync(`cd ${buildDir} && elm make Main.elm --output=Main.js`)

    console.log(`Copying files to output directory...`)
    
    // nosemgrep : detect-non-literal-fs-filename
    if (!fs.existsSync(output)) {
        fs.mkdirSync(output) // nosemgrep : detect-non-literal-fs-filename
    }

    fsExtra.copySync(`${buildDir}/DaprAppShell.js`, `${output}/DaprAppShell.js`)
    fsExtra.copySync(`${buildDir}/Main.js`, `${output}/Main.js`)
    fsExtra.copySync(`${buildDir}/package.json`, `${output}/package.json`)

    if (deleteBuildDir) {
        fs.rmdirSync(buildDir, { recursive: true })
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

async function readElmSources(dirs) {
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
                .filter(entry => entry.isFile() && entry.name.endsWith('.elm')) // nosemgrep : path-join-resolve-traversal
                .map(entry => readElmSource(path.join(currentDir, entry.name))) // nosemgrep : path-join-resolve-traversal
        const subDirSources =
            entries
                .filter(entry => entry.isDirectory()) // nosemgrep : path-join-resolve-traversal
                .map(entry => readDir(path.join(currentDir, entry.name))) // nosemgrep : path-join-resolve-traversal
                .reduce(async (soFarPromise, nextPromise) => {
                    const soFar = await soFarPromise
                    const next = await nextPromise
                    return soFar.concat(next)
                }, Promise.resolve([]))
        return elmSources.concat(await subDirSources)
    }
    const sources =
        await Promise.all(
            dirs.map(async (dir) =>
                Promise.all(
                    await readDir(dir)
                )
            )
        )
    return sources.flat()
}
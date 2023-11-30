'use strict'

// NPM imports
const path = require('path')
const util = require('util')
const fs = require('fs')
const prettier = require("prettier");
const readdir = util.promisify(fs.readdir)
const mkdir = util.promisify(fs.mkdir)
const readFile = util.promisify(fs.readFile)
const fsWriteFile = util.promisify(fs.writeFile)

// Elm imports
const worker = require('./Morphir.Elm.CLI').Elm.Morphir.Elm.CLI.init()


async function make(projectDir, options) {
    const morphirJsonPath = path.join(projectDir, 'morphir.json')
    const morphirJsonContent = await readFile(morphirJsonPath)
    const morphirJson = JSON.parse(morphirJsonContent.toString())
    const sourceFiles = await readElmSources(path.join(projectDir, morphirJson.sourceDirectory))
    return packageDefinitionFromSource(morphirJson, sourceFiles, options)
}

async function packageDefinitionFromSource(morphirJson, sourceFiles, options) {
    return new Promise((resolve, reject) => {
        worker.ports.jsonDecodeError.subscribe(err => {
            reject(err)
        })

        worker.ports.packageDefinitionFromSourceResult.subscribe(([err, ok]) => {
            if (err) {
                reject(err)
            } else {
                resolve(ok)
            }
        })

        const opts = {
            typesOnly: options.typesOnly
        }

        worker.ports.packageDefinitionFromSource.send([opts, morphirJson, sourceFiles])
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
        const entries = await readdir(currentDir, {
            withFileTypes: true
        })
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

async function gen(input, outputPath, options) {
    await mkdir(outputPath, {
        recursive: true
    })
    const morphirIrJson = await readFile(path.resolve(input))
    const opts = options
    opts.limitToModules = options.modulesToInclude ? options.modulesToInclude.split(",") : null
    opts.includeCodecs = options.includeCodecs ? true : false
    opts.filename = options.filename == '' ? '' : options.filename

    if (options.decorations) {
        if (await fileExist(path.resolve(options.decorations))) {
            options.decorationsObj = JSON.parse(await readFile(path.resolve(options.decorations)))
        }
    }

    const fileMap = await generate(opts, JSON.parse(morphirIrJson.toString()))
    const writePromises =
        fileMap.map(async ([
            [dirPath, fileName], content
        ]) => {
            const fileDir = dirPath.reduce((accum, next) => path.join(accum, next), outputPath)
            const filePath = path.join(fileDir, fileName)
            if (await fileExist(filePath)) {
                console.log(`UPDATE - ${filePath}`)
            } else {
                await mkdir(fileDir, {
                    recursive: true
                })
                console.log(`INSERT - ${filePath}`)
            }
            if (options.target == 'TypeScript') {
                return fsWriteFile(filePath, prettier.format(content, { parser: "typescript" }))
            } else {
                return fsWriteFile(filePath, content)
            }
        })
    const filesToDelete = await findFilesToDelete(outputPath, fileMap)
    const deletePromises =
        filesToDelete.map(async (fileToDelete) => {
            console.log(`DELETE - ${fileToDelete}`)
            return fs.unlinkSync(fileToDelete)
        })
    copyRedistributables(options, outputPath)
    return Promise.all(writePromises.concat(deletePromises))
}

function copyRedistributables(options, outputPath) {
    const copyFiles = (src, dest) => {
        const sourceDirectory = path.join(path.dirname(__dirname), 'redistributable', src)
        copyRecursiveSync(sourceDirectory, outputPath)
    }
    if (options.target == 'SpringBoot') {
        copyFiles('SpringBoot', outputPath)
    } else if (options.target == 'Scala' && options.copyDeps) {
        const copyScalaFeature = (feature) => {
            copyFiles(`Scala/sdk/${feature}/src`, outputPath)
            copyFiles(`Scala/sdk/${feature}/src-${options.targetVersion}`, outputPath)
        }
        if (options.includeCodecs) {
            copyScalaFeature('json')
        }
        copyScalaFeature('core')
    } else if (options.target == 'TypeScript') {
        copyFiles('TypeScript/', outputPath)
    } else if (options.target == 'Snowpark') {
        copyFiles('Snowpark/', outputPath)
    }
}

function copyRecursiveSync(src, dest) {
    const exists = fs.existsSync(src);
    if (exists) {
        const stats = exists && fs.statSync(src);
        const isDirectory = exists && stats.isDirectory();
        if (isDirectory) {
            if (!fs.existsSync(dest))
                fs.mkdirSync(dest);
            fs.readdirSync(src).forEach(function (childItemName) {
                copyRecursiveSync(path.join(src, childItemName),
                    path.join(dest, childItemName));
            });
        } else {
            fs.copyFileSync(src, dest);
            console.log(`COPY - ${dest}`)
        }
    }
}

async function generate(options, ir) {
    return new Promise((resolve, reject) => {
        worker.ports.jsonDecodeError.subscribe(err => {
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
        const entries = await readdir(currentDir, {
            withFileTypes: true
        })
        const filesToDelete =
            entries
                .map(entry => [entry, path.resolve(path.join(currentDir, entry.name))])
                .filter(([entry, absolutePath]) => {
                    return entry.isFile() && !generatedFiles.includes(absolutePath)
                })
                .map(([entry, absolutePath]) => {
                    return absolutePath
                })
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
        fileMap.map(([
            [dirPath, fileName], content
        ]) => {
            const fileDir = dirPath.reduce((accum, next) => path.join(accum, next), outputPath)
            return path.resolve(fileDir, fileName)
        })
    return Promise.all(await readDir(outputPath, files))
}

async function writeFile(filePath, content) {
    await mkdir(path.dirname(filePath), {
        recursive: true
    })
    return await fsWriteFile(filePath, content)
}
async function test(projectDir) {
    const morphirIRJsonPath = path.join(projectDir, 'morphir-ir.json')
    const morphirIRJsonContent = await readFile(morphirIRJsonPath)
    const morphirIRJson = JSON.parse(morphirIRJsonContent.toString())
    const morphirTestsJsonPath = path.join(projectDir, 'morphir-tests.json')
    const morphirTestsJsonContent = await readFile(morphirTestsJsonPath)
    const morphirTestsJson = JSON.parse(morphirTestsJsonContent.toString())
    return testResult(morphirIRJson, morphirTestsJson)
}
async function testResult(morphirIRJson, morphirTestsJson) {
    return new Promise((resolve, reject) => {
        worker.ports.jsonDecodeError.subscribe(err => {
            reject(err)
        })
        worker.ports.runTestCasesResultError.subscribe(err => {
            reject(err)
        })
        worker.ports.runTestCasesResult.subscribe(ok => {
            resolve(ok)
        })
        worker.ports.runTestCases.send([morphirIRJson, morphirTestsJson])
    });
}
exports.make = make;
exports.gen = gen;
exports.test = test;
exports.writeFile = writeFile;
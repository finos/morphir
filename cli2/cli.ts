#!/usr/bin/env node

import * as fs from 'fs';
import * as util from 'util';
import * as path from 'path';
import crypto from 'crypto'

const fsWriteFile = util.promisify(fs.writeFile)
const readDir = util.promisify(fs.readdir)
const makeDir = util.promisify(fs.mkdir)
const readFile = util.promisify(fs.readFile)
const accessFile = util.promisify(fs.access)

const worker = require('./Morphir.Elm.CLI').Elm.Morphir.Elm.Cli.init()

async function make(projectDir: string, options: any) {
    const morphirJsonPath: string = path.join(projectDir, 'morphir.json')
    const morphirJsonContent = await readFile(morphirJsonPath)
    const parsedMorphirJson = JSON.parse(morphirJsonContent.toString())

    // All the files in the src directory are read
    const sourcedFiles = await readElmSourceFiles(path.join(projectDir, parsedMorphirJson.sourceDirectory))

    //To check if the morphir-ir.json already exists
    const morphirIrPath: string = path.join(projectDir, 'morphir-ir.json')
    try {
        await accessFile(morphirIrPath, fs.constants.F_OK)
        console.log(`${morphirIrPath}, will be passed to the worker along side changed to update the ir`)
    } catch (err) {
        console.log(`${err}, not found`)
        // return packageDefinitionFromSource(parsedMorphirJson, sourcedFiles, options)
    }
}

//generating a hash with md5 algorithm for the content of the read file
const hashedContent = (contentOfFile: any) => {
    let hash = crypto.createHash('md5');
    let data = hash.update(contentOfFile, 'utf8')
    let gen_hash = data.digest('hex')
    return gen_hash;
}

// async function packageDefinitionFromSource(parsedMorphirJson: any, sourcedFiles: any, options: any,) {
//     return new Promise((resolve, reject) => {
//         worker.ports.jsonDecodeError.subscribe((err: any) => {
//             reject(err)
//         })

//         worker.ports.packageDefinitionFromSourceResult.subscribe(([err, ok]: any) => {
//             if (err) {
//                 reject(err)
//             } else {
//                 resolve(ok)
//             }
//         })

//         const opts = {
//             typesOnly: options.typesOnly
//         }

//         worker.ports.packageDefinitionFromSource.send([opts, parsedMorphirJson, sourcedFiles])
//     })
// }

function pathDifference(keys1: Array<string>, keys2: Array<string>) {
    return keys1.filter(item => keys2.indexOf(item) < 0)
}

async function differenceInHash(hashFilePath: string, filePath: string,
    fileHash: Map<string, string>, fileChangesMap: Map<string, Array<string>>, hashJson: any) {

    const readContent = await readFile(filePath)
    const hash = hashedContent(readContent)
    for (let key in hashJson) {
        fileHash.set(key, hashJson[key])
    }
    if (fileHash.has(filePath)) {
        if (fileHash.get(filePath) && (fileHash.get(filePath) !== hash)) {
            fileHash.set(filePath, hash)
            fileChangesMap.set(filePath, ['Updated', readContent.toString()])
        }
    }
    else {
        fileHash.set(filePath, hash)
        fileChangesMap.set(filePath, ['Insert', readContent.toString()])
    }
    let jsonObject = Object.fromEntries(fileHash)
    await fsWriteFile(hashFilePath, JSON.stringify(jsonObject, null, 2))
    let fileChangeObject = Object.fromEntries(fileChangesMap)
    return fileChangeObject
}

async function readElmSourceFiles(dir: string) {
    let fileHash = new Map<string, string>();
    let fileChangesMap = new Map<string, Array<string>>()
    let newPathList: Array<string> = []
    const readSourceFile = async function (filePath: string) {
        const hashFilePath: string = path.join(dir, '../morphir-hash.json')
        newPathList.push(filePath)
        try {
            await accessFile(hashFilePath)
            const readHashFile = await readFile(hashFilePath)
            let hashJson = JSON.parse(readHashFile.toString())
            let oldPathList = Object.keys(hashJson)
            await differenceInHash(hashFilePath, filePath, fileHash, fileChangesMap, hashJson)
            let difference = pathDifference(oldPathList, newPathList)
            difference.map(file => {
                fileHash.delete(file)
                fileChangesMap.set(file, ['Deleted'])
            })
            let jsonObject = Object.fromEntries(fileHash)
            await fsWriteFile(hashFilePath, JSON.stringify(jsonObject, null, 2))
        } catch (err) {
            const readContent = await readFile(filePath)
            const hash = hashedContent(readContent)
            fileHash.set(filePath, hash)
            let jsonObject = Object.fromEntries(fileHash)
            await fsWriteFile(hashFilePath, JSON.stringify(jsonObject, null, 2))
            return {
                path: filePath,
                content: readContent.toString()
            }
        }
    }
    const readDirectory = async function (currentDir: string) {
        const entries = await readDir(currentDir, {
            withFileTypes: true
        })
        const elmSources =
            entries
                .filter(entry => entry.isFile() && entry.name.endsWith('.elm'))
                .map(async entry => {
                    readSourceFile(path.join(currentDir, entry.name))
                })
        const subDirectories: any =
            entries
                .filter(entry => entry.isDirectory())
                .map(entry => readDirectory(path.join(currentDir, entry.name)))
                .reduce(async (currentResult, nextResult) => {
                    const current = await currentResult
                    const next = await nextResult
                    return current.concat(next)
                }, Promise.resolve([]))
        return elmSources.concat(await subDirectories)
    }
    return Promise.all(await readDirectory(dir))
}

async function writeFile(filePath: string, content: string) {
    await makeDir(path.dirname(filePath), {
        recursive: true
    })
    return await fsWriteFile(filePath, content)
}

export = { make, writeFile }
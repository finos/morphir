#!/usr/bin/env node

import * as fs from 'fs';
import * as util from 'util';
import * as path from 'path';
import crypto from 'crypto'
import * as FileChanges from './FileChanges'

const fsExists = util.promisify(fs.exists)
const fsWriteFile = util.promisify(fs.writeFile)
const readDir = util.promisify(fs.readdir)
const makeDir = util.promisify(fs.mkdir)
const fsReadFile = util.promisify(fs.readFile)
const accessFile = util.promisify(fs.access)

const worker = require('./../Morphir.Elm.CLI').Elm.Morphir.Elm.CLI.init()

async function make(projectDir: string, options: any) {
    const morphirJsonPath: string = path.join(projectDir, 'morphir.json')
    const morphirJson = JSON.parse((await fsReadFile(morphirJsonPath)).toString())

    const hashFilePath = path.join(projectDir, 'morphir-hashes.json')
    const oldContentHashes = await readContentHashes(hashFilePath)
    const fileChanges = await FileChanges.detectChanges(oldContentHashes, path.join(projectDir, morphirJson.sourceDirectory))

    reportFileChangeStats(fileChanges)

    //To check if the morphir-ir.json already exists
    let morphirIR: any = null
    const morphirIrPath: string = path.join(projectDir, 'morphir-ir.json')
    try {
        const morphirIRFile = await fsReadFile(morphirIrPath)
        morphirIR = JSON.parse(morphirIRFile.toString())
    } catch (err) {
        console.log(`${err}, not found`)
    }
    const updatedIR = await packageDefinitionFromSource(morphirJson, fileChanges, options, morphirIR)
    await writeContentHashes(hashFilePath, FileChanges.toContentHashes(fileChanges))
    return updatedIR
}

//generating a hash with md5 algorithm for the content of the read file
const hashedContent = (contentOfFile: any) => {
    let hash = crypto.createHash('md5');
    let data = hash.update(contentOfFile, 'utf8')
    let gen_hash = data.digest('hex')
    return gen_hash;
}

async function packageDefinitionFromSource(morphirJson: any, fileChanges: FileChanges.FileChanges, options: any, morphirIR: any) {
    return new Promise((resolve, reject) => {
        worker.ports.jsonDecodeError.subscribe((err: any) => {
            reject(err)
        })

        worker.ports.buildIncrementallyCompleted.subscribe(([err, ok]: any) => {
            if (err) {
                reject(err)
            } else {
                resolve(ok)
            }
        })

        const opts = {
            typesOnly: options.typesOnly
        }

        worker.ports.buildIncrementally.send({
            options: opts,
            packageInfo: morphirJson,
            fileChanges: FileChanges.toElmJson(fileChanges),
            distribution: morphirIR
        })
    })
}

function pathDifference(keys1: Array<string>, keys2: Array<string>) {
    return keys1.filter(item => keys2.indexOf(item) < 0)
}

async function differenceInHash(hashFilePath: string, filePath: string,
    fileHash: Map<string, string>, fileChangesMap: Map<string, Array<string>>, hashJson: any) {

    const readContent = await fsReadFile(filePath)
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


/**
 * Read content hashes from a file.
 * 
 * @param filePath file path to read hashes from
 * @returns map of hashes
 */
async function readContentHashes(filePath: string): Promise<Map<FileChanges.Path, FileChanges.Hash>> {
    // Check if the file exists
    if (await fsExists(filePath)) {
        const contentHashesJson = JSON.parse((await fsReadFile(filePath)).toString())
        const contentHashesMap: Map<FileChanges.Path, FileChanges.Hash> = new Map<FileChanges.Path, FileChanges.Hash>()
        for (let path in contentHashesJson) {
            contentHashesMap.set(path, contentHashesJson[path])
        }
        return contentHashesMap
    } else {
        return new Map<FileChanges.Path, FileChanges.Hash>()
    }
}

/**
 * Write content hashes into a file.
 * 
 * @param filePath file path to read hashes from
 * @returns map of hashes
 */
async function writeContentHashes(filePath: string, hashes: Map<FileChanges.Path, FileChanges.Hash>): Promise<void> {
    const jsonObject: { [index: string]: string } = {}
    for (let [path, hash] of hashes) {
        jsonObject[path] = hash
    }
    await writeFile(filePath, JSON.stringify(jsonObject, null, 4))
}


function reportFileChangeStats(fileChanges: FileChanges.FileChanges): void {
    const stats: FileChanges.Stats = FileChanges.toStats(fileChanges)
    const message = [
        `- inserted:  ${stats.inserted}`,
        `- updated:   ${stats.updated}`,
        `- deleted:   ${stats.deleted}`,
        `- unchanged: ${stats.unchanged}`
    ].join('\n  ')
    console.log(`The following file changes were detected:\n  ${message}`)
}

async function writeFile(filePath: string, content: string) {
    await makeDir(path.dirname(filePath), {
        recursive: true
    })
    return await fsWriteFile(filePath, content)
}

export = { make, writeFile }
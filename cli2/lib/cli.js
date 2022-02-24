#!/usr/bin/env node
"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    Object.defineProperty(o, k2, { enumerable: true, get: function() { return m[k]; } });
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || function (mod) {
    if (mod && mod.__esModule) return mod;
    var result = {};
    if (mod != null) for (var k in mod) if (k !== "default" && Object.prototype.hasOwnProperty.call(mod, k)) __createBinding(result, mod, k);
    __setModuleDefault(result, mod);
    return result;
};
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
const fs = __importStar(require("fs"));
const util = __importStar(require("util"));
const path = __importStar(require("path"));
const crypto_1 = __importDefault(require("crypto"));
const fsWriteFile = util.promisify(fs.writeFile);
const readDir = util.promisify(fs.readdir);
const makeDir = util.promisify(fs.mkdir);
const readFile = util.promisify(fs.readFile);
const accessFile = util.promisify(fs.access);
const worker = require('./Morphir.Elm.CLI').Elm.Morphir.Elm.Cli.init();
async function make(projectDir, options) {
    const morphirJsonPath = path.join(projectDir, 'morphir.json');
    const morphirJsonContent = await readFile(morphirJsonPath);
    const parsedMorphirJson = JSON.parse(morphirJsonContent.toString());
    // All the files in the src directory are read
    const sourcedFiles = await readElmSourceFiles(path.join(projectDir, parsedMorphirJson.sourceDirectory));
    //To check if the morphir-ir.json already exists
    const morphirIrPath = path.join(projectDir, 'morphir-ir.json');
    try {
        await accessFile(morphirIrPath, fs.constants.F_OK);
        console.log(`${morphirIrPath}, will be passed to the worker along side changed to update the ir`);
    }
    catch (err) {
        console.log(`${err}, not found`);
        return packageDefinitionFromSource(parsedMorphirJson, sourcedFiles, options);
    }
}
//generating a hash with md5 algorithm for the content of the read file
const hashedContent = (contentOfFile) => {
    let hash = crypto_1.default.createHash('md5');
    let data = hash.update(contentOfFile, 'utf8');
    let gen_hash = data.digest('hex');
    return gen_hash;
};
async function packageDefinitionFromSource(parsedMorphirJson, sourcedFiles, options) {
    return new Promise((resolve, reject) => {
        worker.ports.jsonDecodeError.subscribe((err) => {
            reject(err);
        });
        worker.ports.packageDefinitionFromSourceResult.subscribe(([err, ok]) => {
            if (err) {
                reject(err);
            }
            else {
                resolve(ok);
            }
        });
        const opts = {
            typesOnly: options.typesOnly
        };
        worker.ports.packageDefinitionFromSource.send([opts, parsedMorphirJson, sourcedFiles]);
    });
}
function pathDifference(keys1, keys2) {
    return keys1.filter(item => keys2.indexOf(item) < 0);
}
async function differenceAndHash(hashFilePath, filePath, fileHash, fileChangesMap, hashJson) {
    const readContent = await readFile(filePath);
    const hash = hashedContent(readContent);
    for (let key in hashJson) {
        fileHash.set(key, hashJson[key]);
    }
    if (fileHash.has(filePath)) {
        if (fileHash.get(filePath)) {
            if (fileHash.get(filePath) !== hash) {
                fileHash.set(filePath, hash);
                fileChangesMap.set(filePath, ['Updated', readContent.toString()]);
            }
        }
    }
    else {
        fileHash.set(filePath, hash);
        fileChangesMap.set(filePath, ['Insert', readContent.toString()]);
    }
    let jsonObject = Object.fromEntries(fileHash);
    await fsWriteFile(hashFilePath, JSON.stringify(jsonObject, null, 2));
    let fileChangeObject = Object.fromEntries(fileChangesMap);
    return fileChangeObject;
}
async function readElmSourceFiles(dir) {
    let fileHash = new Map();
    let fileChangesMap = new Map();
    let keys2 = [];
    const readSourceFile = async function (filePath) {
        const hashFilePath = path.join(dir, '../morphir-hash.json');
        keys2.push(filePath);
        try {
            await accessFile(hashFilePath);
            const readHashFile = await readFile(hashFilePath);
            let hashJson = JSON.parse(readHashFile.toString());
            let keys1 = Object.keys(hashJson);
            await differenceAndHash(hashFilePath, filePath, fileHash, fileChangesMap, hashJson);
            let missing = pathDifference(keys1, keys2);
            missing.map(file => {
                fileHash.delete(file);
                fileChangesMap.set(file, ['Deleted', 'No content']);
            });
            let jsonObject = Object.fromEntries(fileHash);
            await fsWriteFile(hashFilePath, JSON.stringify(jsonObject, null, 2));
        }
        catch (err) {
            const readContent = await readFile(filePath);
            const hash = hashedContent(readContent);
            fileHash.set(filePath, hash);
            let jsonObject = Object.fromEntries(fileHash);
            await fsWriteFile(hashFilePath, JSON.stringify(jsonObject, null, 2));
            return {
                path: filePath,
                content: readContent.toString()
            };
        }
    };
    const readDirectory = async function (currentDir) {
        const entries = await readDir(currentDir, {
            withFileTypes: true
        });
        const elmSources = entries
            .filter(entry => entry.isFile() && entry.name.endsWith('.elm'))
            .map(async (entry) => {
            readSourceFile(path.join(currentDir, entry.name));
        });
        const subDirectories = entries
            .filter(entry => entry.isDirectory())
            .map(entry => readDirectory(path.join(currentDir, entry.name)))
            .reduce(async (currentResult, nextResult) => {
            const current = await currentResult;
            const next = await nextResult;
            return current.concat(next);
        }, Promise.resolve([]));
        return elmSources.concat(await subDirectories);
    };
    return Promise.all(await readDirectory(dir));
}
async function writeFile(filePath, content) {
    await makeDir(path.dirname(filePath), {
        recursive: true
    });
    return await fsWriteFile(filePath, content);
}
module.exports = { make, writeFile };

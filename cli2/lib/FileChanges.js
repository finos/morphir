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
Object.defineProperty(exports, "__esModule", { value: true });
exports.hasChanges = exports.toStats = exports.toFileSnapshotJson = exports.toFileChangesJson = exports.toContentHashes = exports.detectChanges = void 0;
const util = __importStar(require("util"));
const fs = __importStar(require("fs"));
const path = __importStar(require("path"));
const crypto_1 = __importDefault(require("crypto"));
const fsExists = util.promisify(fs.exists);
const fsReadDir = util.promisify(fs.readdir);
const fsReadFile = util.promisify(fs.readFile);
function Insert(content, hash) {
    return {
        kind: 'Insert',
        content: content,
        hash: hash
    };
}
function Update(content, hash) {
    return {
        kind: 'Update',
        content: content,
        hash: hash
    };
}
function Delete() {
    return {
        kind: 'Delete'
    };
}
function NoChange(content, hash) {
    return {
        kind: 'NoChange',
        content: content,
        hash: hash
    };
}
async function detectChanges(oldContentHashes, dirPath) {
    // Check if the directory exists
    if (await fsExists(dirPath)) {
        // If it does exist detect the changes based on the current file system state
        const fileChanges = await detectChangesWithinDirectory(oldContentHashes, dirPath);
        // Deleted files can't be detected by just looking at current files so we need to infer that from the old hashes
        const oldPaths = new Set(oldContentHashes.keys());
        // Remove the paths that still exist
        for (let newPath of fileChanges.keys()) {
            oldPaths.delete(newPath);
        }
        // For all the remaining paths we report that they were deleted
        for (let oldPath of oldPaths) {
            fileChanges.set(oldPath, Delete());
        }
        return fileChanges;
    }
    else {
        // If it doesn't, then all the previously existing fiels are gone so we report that
        const fileChanges = new Map();
        const oldPaths = new Set(oldContentHashes.keys());
        for (let oldPath of oldPaths) {
            fileChanges.set(oldPath, Delete());
        }
        return fileChanges;
    }
}
exports.detectChanges = detectChanges;
async function detectChangesWithinDirectory(oldContentHashes, dirPath) {
    const dirEntries = await fsReadDir(dirPath, { withFileTypes: true });
    // Detect file changes in current directory
    const fileChangesInCurrentDir = new Map(await Promise.all(dirEntries
        .filter((entry) => entry.isFile())
        .map(async (fileEntry) => {
        const filePath = path.join(dirPath, fileEntry.name); // nosemgrep : path-join-resolve-traversal
        const maybeFileChange = await detectChangeOfSingleFile(oldContentHashes.get(filePath), filePath);
        const fileChangeEntry = [filePath, maybeFileChange];
        return fileChangeEntry;
    })));
    // Detect changes in subdirectories    
    const fileChangesInSubDirs = await Promise.all(dirEntries
        .filter((entry) => entry.isDirectory())
        .map(async (dirEntry) => detectChangesWithinDirectory(oldContentHashes, path.join(dirPath, dirEntry.name))) // nosemgrep : path-join-resolve-traversal
    );
    // Merge changes in current directory with changes in subdirectories    
    return fileChangesInSubDirs
        .concat(fileChangesInCurrentDir)
        .reduce(setAll, new Map());
}
/**
 * Detect change for one specific file path. When there is no change it returns undefined.
 *
 * @param oldContentHash content hash that was calculated previously or undefined
 * @param filePath the file path to detect changes on
 */
async function detectChangeOfSingleFile(oldContentHash, filePath) {
    // Check if the file exists
    if (await fsExists(filePath)) {
        // If it does, read the content
        const content = (await fsReadFile(filePath)).toString();
        // Generate a new hash based on the current content
        const newContentHash = calculateContentHash(content);
        // If there is no previous hash then treat it as a new file
        if (!oldContentHash) {
            return Insert(content, newContentHash);
        }
        else {
            // Check if it's the same as the previous hash
            if (oldContentHash === newContentHash) {
                // If it's the same there was no change
                return NoChange(content, oldContentHash);
            }
            else {
                // If the hashes are different then it's an update
                // We are also returning the new hash so that we can save it
                return Update(content, newContentHash);
            }
        }
    }
    else {
        // If it doesn't exist then it was deleted
        return Delete();
    }
}
/**
 * Extract content hashes from a file changes map.
 *
 * @param fileChanges map of file changes
 * @returns map of content hashes
 */
function toContentHashes(fileChanges) {
    const contentHashes = new Map();
    for (let [path, fileChange] of fileChanges) {
        if (fileChange.kind == 'Insert' || fileChange.kind == 'Update' || fileChange.kind == 'NoChange') {
            contentHashes.set(path, fileChange.hash);
        }
    }
    return contentHashes;
}
exports.toContentHashes = toContentHashes;
/**
 * Turn file changes into the JSON format expected by Elm.
 *
 * @param fileChanges file changes map
 * @returns JSON representation thet's expected by Elm
 */
function toFileChangesJson(fileChanges) {
    const fileChangeToJson = (fileChange) => {
        if (fileChange.kind == 'Insert') {
            return ['Insert', fileChange.content];
        }
        else if (fileChange.kind == 'Update') {
            return ['Update', fileChange.content];
        }
        else {
            return ['Delete'];
        }
    };
    const fileChangesJson = {};
    for (let [path, fileChange] of fileChanges) {
        if (fileChange.kind != 'NoChange') {
            fileChangesJson[path] = fileChangeToJson(fileChange);
        }
    }
    return fileChangesJson;
}
exports.toFileChangesJson = toFileChangesJson;
function toFileSnapshotJson(fileChanges) {
    const inserts = {};
    for (let [path, fileChange] of fileChanges) {
        if (fileChange.kind == 'Insert') {
            inserts[path] = fileChange.content;
        }
        else if (fileChange.kind == 'Update') {
            inserts[path] = fileChange.content;
        }
        else if (fileChange.kind == 'Delete') {
            // deleted fiels are simply not inserted
        }
        else {
            inserts[path] = fileChange.content;
        }
    }
    return inserts;
}
exports.toFileSnapshotJson = toFileSnapshotJson;
/**
 *
 * @param fileChanges file changes
 * @returns stats about how many files were inserted, updated, deleted or remained unchanged
 */
function toStats(fileChanges) {
    const stats = {
        inserted: 0,
        updated: 0,
        deleted: 0,
        unchanged: 0
    };
    for (let [_, fileChange] of fileChanges) {
        if (fileChange.kind == 'Insert') {
            stats.inserted += 1;
        }
        else if (fileChange.kind == 'Update') {
            stats.updated += 1;
        }
        else if (fileChange.kind == 'Delete') {
            stats.deleted += 1;
        }
        else {
            stats.unchanged += 1;
        }
    }
    return stats;
}
exports.toStats = toStats;
/**
 * Checks if there were any file changes or every file is unchanged.
 *
 * @param stats file change stats obtained using `toStats`
 * @returns true if there was at least one insert, update or delete
 */
function hasChanges(stats) {
    return stats.inserted > 0 || stats.updated > 0 || stats.deleted > 0;
}
exports.hasChanges = hasChanges;
/**
 * Calculate a has for some string content.
 *
 * @param content content to hash
 * @returns the hash
 */
function calculateContentHash(content) {
    return crypto_1.default
        .createHash('md5')
        .update(content, 'utf8')
        .digest('hex');
}
/**
 * Set entries of an existing map based on a new map.
 *
 * @param newMap the new map to extract all the values to add from
 * @param currentMap the current map that should be updated with new entries
 * @returns
 */
function setAll(newMap, currentMap) {
    for (let [key, value] of newMap) {
        currentMap.set(key, value);
    }
    return currentMap;
}

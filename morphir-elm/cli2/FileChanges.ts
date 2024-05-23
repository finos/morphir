import * as util from 'util'
import * as fs from 'fs'
import * as path from 'path'
import crypto from 'crypto'

const fsExists = util.promisify(fs.exists)
const fsReadDir = util.promisify(fs.readdir)
const fsReadFile = util.promisify(fs.readFile)

export type Path = string

export type Hash = string

export type FileChange = Insert | Update | Delete | NoChange
interface Insert {
    kind: 'Insert'
    content: string
    hash: Hash
}
function Insert(content: string, hash: Hash): Insert {
    return {
        kind: 'Insert',
        content: content,
        hash: hash
    }
}
interface Update {
    kind: 'Update'
    content: string
    hash: Hash
}
function Update(content: string, hash: Hash): Update {
    return {
        kind: 'Update',
        content: content,
        hash: hash
    }
}
interface Delete {
    kind: 'Delete'
}
function Delete(): Delete {
    return {
        kind: 'Delete'
    }
}
interface NoChange {
    kind: 'NoChange'
    content: string
    hash: Hash
}
function NoChange(content: string, hash: Hash): NoChange {
    return {
        kind: 'NoChange',
        content: content,
        hash: hash
    }
}

export type FileChanges = Map<Path, FileChange>

export async function detectChanges(oldContentHashes: Map<Path, Hash>, dirPath: Path): Promise<Map<Path, FileChange>> {
    // Check if the directory exists
    if (await fsExists(dirPath)) {
        // If it does exist detect the changes based on the current file system state
        const fileChanges: Map<Path, FileChange> = await detectChangesWithinDirectory(oldContentHashes, dirPath)
        // Deleted files can't be detected by just looking at current files so we need to infer that from the old hashes
        const oldPaths: Set<Path> = new Set(oldContentHashes.keys())
        // Remove the paths that still exist
        for (let newPath of fileChanges.keys()) {
            oldPaths.delete(newPath)
        }
        // For all the remaining paths we report that they were deleted
        for (let oldPath of oldPaths) {
            fileChanges.set(oldPath, Delete())
        }
        return fileChanges
    } else {
        // If it doesn't, then all the previously existing fiels are gone so we report that
        const fileChanges: Map<Path, FileChange> = new Map<Path, FileChange>()
        const oldPaths: Set<Path> = new Set(oldContentHashes.keys())
        for (let oldPath of oldPaths) {
            fileChanges.set(oldPath, Delete())
        }
        return fileChanges
    }
}

async function detectChangesWithinDirectory(oldContentHashes: Map<Path, Hash>, dirPath: Path): Promise<Map<Path, FileChange>> {
    const dirEntries = await fsReadDir(dirPath, { withFileTypes: true })
    // Detect file changes in current directory
    const fileChangesInCurrentDir: Map<Path, FileChange> =
        new Map(
            await Promise.all(
                dirEntries
                    .filter((entry: fs.Dirent) => entry.isFile())
                    .map(async (fileEntry: fs.Dirent) => {
                        const filePath = path.join(dirPath, fileEntry.name) // nosemgrep : path-join-resolve-traversal
                        const maybeFileChange = await detectChangeOfSingleFile(oldContentHashes.get(filePath), filePath)
                        const fileChangeEntry: [Path, FileChange] = [filePath, maybeFileChange]
                        return fileChangeEntry

                    })
            )
        )
    // Detect changes in subdirectories    
    const fileChangesInSubDirs: Map<Path, FileChange>[] =
        await Promise.all(
            dirEntries
                .filter((entry: fs.Dirent) => entry.isDirectory())
                .map(async (dirEntry: fs.Dirent) => detectChangesWithinDirectory(oldContentHashes, path.join(dirPath, dirEntry.name))) // nosemgrep : path-join-resolve-traversal
        )
    // Merge changes in current directory with changes in subdirectories    
    return fileChangesInSubDirs
        .concat(fileChangesInCurrentDir)
        .reduce(setAll, new Map<Path, FileChange>())
}

/**
 * Detect change for one specific file path. When there is no change it returns undefined.
 * 
 * @param oldContentHash content hash that was calculated previously or undefined
 * @param filePath the file path to detect changes on
 */
async function detectChangeOfSingleFile(oldContentHash: Hash | undefined, filePath: Path): Promise<FileChange> {
    // Check if the file exists
    if (await fsExists(filePath)) {
        // If it does, read the content
        const content = (await fsReadFile(filePath)).toString()
        // Generate a new hash based on the current content
        const newContentHash = calculateContentHash(content)
        // If there is no previous hash then treat it as a new file
        if (!oldContentHash) {
            return Insert(content, newContentHash)
        } else {
            // Check if it's the same as the previous hash
            if (oldContentHash === newContentHash) {
                // If it's the same there was no change
                return NoChange(content, oldContentHash)
            } else {
                // If the hashes are different then it's an update
                // We are also returning the new hash so that we can save it
                return Update(content, newContentHash)
            }
        }
    } else {
        // If it doesn't exist then it was deleted
        return Delete()
    }
}

/**
 * Extract content hashes from a file changes map.
 * 
 * @param fileChanges map of file changes
 * @returns map of content hashes
 */
export function toContentHashes(fileChanges: Map<Path, FileChange>): Map<Path, Hash> {
    const contentHashes: Map<Path, Hash> = new Map<Path, Hash>()
    for (let [path, fileChange] of fileChanges) {
        if (fileChange.kind == 'Insert' || fileChange.kind == 'Update' || fileChange.kind == 'NoChange') {
            contentHashes.set(path, fileChange.hash)
        }
    }
    return contentHashes
}

/**
 * Turn file changes into the JSON format expected by Elm.
 * 
 * @param fileChanges file changes map
 * @returns JSON representation thet's expected by Elm
 */
export function toFileChangesJson(fileChanges: Map<Path, FileChange>): { [index: string]: any } {
    const fileChangeToJson = (fileChange: Insert | Update | Delete): any => {
        if (fileChange.kind == 'Insert') {
            return ['Insert', fileChange.content]
        } else if (fileChange.kind == 'Update') {
            return ['Update', fileChange.content]
        } else {
            return ['Delete']
        }
    }

    const fileChangesJson: { [index: string]: any } = {}
    for (let [path, fileChange] of fileChanges) {
        if (fileChange.kind != 'NoChange') {
            fileChangesJson[path] = fileChangeToJson(fileChange)
        }
    }
    return fileChangesJson
}

export function toFileSnapshotJson(fileChanges: Map<Path, FileChange>): { [index: string]: string } {
    const inserts: { [index: string]: string } = {}
    for (let [path, fileChange] of fileChanges) {
        if (fileChange.kind == 'Insert') {
            inserts[path] = fileChange.content
        } else if (fileChange.kind == 'Update') {
            inserts[path] = fileChange.content
        } else if (fileChange.kind == 'Delete') {
            // deleted fiels are simply not inserted
        } else {
            inserts[path] = fileChange.content
        }
    }
    return inserts
}

export interface Stats {
    inserted: number
    updated: number
    deleted: number
    unchanged: number
}

/**
 * 
 * @param fileChanges file changes
 * @returns stats about how many files were inserted, updated, deleted or remained unchanged
 */
export function toStats(fileChanges: Map<Path, FileChange>): Stats {
    const stats: Stats = {
        inserted: 0,
        updated: 0,
        deleted: 0,
        unchanged: 0
    }
    for (let [_, fileChange] of fileChanges) {
        if (fileChange.kind == 'Insert') {
            stats.inserted += 1
        } else if (fileChange.kind == 'Update') {
            stats.updated += 1
        } else if (fileChange.kind == 'Delete') {
            stats.deleted += 1
        } else {
            stats.unchanged += 1
        }
    }
    return stats
}

/**
 * Checks if there were any file changes or every file is unchanged.
 * 
 * @param stats file change stats obtained using `toStats`
 * @returns true if there was at least one insert, update or delete
 */
export function hasChanges(stats: Stats): boolean {
    return stats.inserted > 0 || stats.updated > 0 || stats.deleted > 0
}

/**
 * Calculate a has for some string content.
 * 
 * @param content content to hash
 * @returns the hash
 */
function calculateContentHash(content: string): string {
    return crypto
        .createHash('md5')
        .update(content, 'utf8')
        .digest('hex')
}

/**
 * Set entries of an existing map based on a new map.
 * 
 * @param newMap the new map to extract all the values to add from
 * @param currentMap the current map that should be updated with new entries
 * @returns 
 */
function setAll<K, V>(newMap: Map<K, V>, currentMap: Map<K, V>): Map<K, V> {
    for (let [key, value] of newMap) {
        currentMap.set(key, value)
    }
    return currentMap
}
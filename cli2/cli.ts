#!/usr/bin/env node

import * as fs from "fs";
import * as util from "util";
import * as path from "path";
import * as FileChanges from "./FileChanges";

const fsExists = util.promisify(fs.exists);
const fsWriteFile = util.promisify(fs.writeFile);
const fsMakeDir = util.promisify(fs.mkdir);
const fsReadFile = util.promisify(fs.readFile);
const readdir = util.promisify(fs.readdir);

const worker = require("./../Morphir.Elm.CLI").Elm.Morphir.Elm.CLI.init();

interface MorphirJson {
  name: string;
  sourceDirectory: string;
  exposedModules: string[];
}

async function make(
  projectDir: string,
  options: any
): Promise<string | undefined> {
  // Morphir specific files expected to be in the project directory
  const morphirJsonPath: string = path.join(projectDir, "morphir.json"); // nosemgrep : path-join-resolve-traversal
  const hashFilePath: string = path.join(projectDir, "morphir-hashes.json");  // nosemgrep : path-join-resolve-traversal
  const morphirIrPath: string = path.join(projectDir, "morphir-ir.json"); // nosemgrep : path-join-resolve-traversal

  // Load the `morphir.json` file that describes the project
  const morphirJson: MorphirJson = JSON.parse(
    (await fsReadFile(morphirJsonPath)).toString()
  );

  // check the status of the build incremental flag
  if (options.buildIncrementally == false) {
    // We invoke file change detection but pass in no hashes which will generate inserts only
    const fileChanges = await FileChanges.detectChanges(
      new Map(),
      path.join(projectDir, morphirJson.sourceDirectory) // nosemgrep : path-join-resolve-traversal
    );
    const fileSnapshot = FileChanges.toFileSnapshotJson(fileChanges);
    const newIR: string = await buildFromScratch(
      morphirJson,
      fileSnapshot,
      options
    );
    await writeContentHashes(
      hashFilePath,
      FileChanges.toContentHashes(fileChanges)
    );
    return newIR;
  } else {
    if ((await fsExists(morphirIrPath)) && (await fsExists(hashFilePath))) {
      const oldContentHashes = await readContentHashes(hashFilePath);
      const fileChanges = await FileChanges.detectChanges(
        oldContentHashes,
        path.join(projectDir, morphirJson.sourceDirectory) // nosemgrep : path-join-resolve-traversal
      );
      if (reportFileChangeStats(fileChanges)) {
        console.log(
          "There were file changes and there is an existing IR. Building incrementally."
        );
        const previousIR: string = (await fsReadFile(morphirIrPath)).toString();
        const updatedIR: string = await buildIncrementally(
          morphirJson,
          fileChanges,
          options,
          previousIR
        );
        await writeContentHashes(
          hashFilePath,
          FileChanges.toContentHashes(fileChanges)
        );
        return updatedIR;
      } else {
        console.log(
          "There were no file changes and there is an existing IR. No actions needed."
        );
      }
    } else {
      console.log("Building from scratch.");
      // We invoke file change detection but pass in no hashes which will generate inserts only
      const fileChanges = await FileChanges.detectChanges(
        new Map(),
        path.join(projectDir, morphirJson.sourceDirectory) // nosemgrep : path-join-resolve-traversal
      );
      const fileSnapshot = FileChanges.toFileSnapshotJson(fileChanges);
      const newIR: string = await buildFromScratch(
        morphirJson,
        fileSnapshot,
        options
      );
      await writeContentHashes(
        hashFilePath,
        FileChanges.toContentHashes(fileChanges)
      );
      return newIR;
    }
  }
}

async function buildFromScratch(
  morphirJson: any,
  fileSnapshot: { [index: string]: string },
  options: any
): Promise<string> {
  return new Promise((resolve, reject) => {
    worker.ports.decodeFailed.subscribe((err: any) => {
      reject(err);
    });

    worker.ports.buildFailed.subscribe((err: any) => {
      reject(err);
    });

    worker.ports.reportProgress.subscribe((message: any) => {
      console.log(message);
    });

    worker.ports.buildCompleted.subscribe(([err, ok]: any) => {
      if (err) {
        reject(err);
      } else {
        resolve(JSON.stringify(ok, null, 4));
      }
    });

    const opts = {
      typesOnly: options.typesOnly,
    };

    worker.ports.buildFromScratch.send({
      options: opts,
      packageInfo: morphirJson,
      fileSnapshot: fileSnapshot,
    });
  });
}

async function buildIncrementally(
  morphirJson: any,
  fileChanges: FileChanges.FileChanges,
  options: any,
  previousIR: string
): Promise<string> {
  return new Promise((resolve, reject) => {
    worker.ports.decodeFailed.subscribe((err: any) => {
      reject(err);
    });

    worker.ports.buildFailed.subscribe((err: any) => {
      reject(err);
    });

    worker.ports.reportProgress.subscribe((message: any) => {
      console.log(message);
    });

    worker.ports.buildCompleted.subscribe(([err, ok]: any) => {
      if (err) {
        reject(err);
      } else {
        resolve(JSON.stringify(ok, null, 4));
      }
    });

    const opts = {
      typesOnly: options.typesOnly,
    };

    let maybeDistribution = null;
    if (previousIR) {
      maybeDistribution = JSON.parse(previousIR);
    }

    worker.ports.buildIncrementally.send({
      options: opts,
      packageInfo: morphirJson,
      fileChanges: FileChanges.toFileChangesJson(fileChanges),
      distribution: maybeDistribution,
    });
  });
}

/**
 * Read content hashes from a file.
 *
 * @param filePath file path to read hashes from
 * @returns map of hashes
 */
async function readContentHashes(
  filePath: string
): Promise<Map<FileChanges.Path, FileChanges.Hash>> {
  // Check if the file exists
  if (await fsExists(filePath)) {
    const contentHashesJson = JSON.parse(
      (await fsReadFile(filePath)).toString()
    );
    const contentHashesMap: Map<FileChanges.Path, FileChanges.Hash> = new Map<
      FileChanges.Path,
      FileChanges.Hash
    >();
    for (let path in contentHashesJson) {
      contentHashesMap.set(path, contentHashesJson[path]);
    }
    return contentHashesMap;
  } else {
    return new Map<FileChanges.Path, FileChanges.Hash>();
  }
}

/**
 * Write content hashes into a file.
 *
 * @param filePath file path to read hashes from
 * @returns map of hashes
 */
async function writeContentHashes(
  filePath: string,
  hashes: Map<FileChanges.Path, FileChanges.Hash>
): Promise<void> {
  const jsonObject: { [index: string]: string } = {};
  for (let [path, hash] of hashes) {
    jsonObject[path] = hash;
  }
  await writeFile(filePath, JSON.stringify(jsonObject, null, 4)); // nosemgrep : detect-non-literal-fs-filename
}

function reportFileChangeStats(fileChanges: FileChanges.FileChanges): boolean {
  const stats: FileChanges.Stats = FileChanges.toStats(fileChanges);
  if (FileChanges.hasChanges(stats)) {
    const message = [
      `- inserted:  ${stats.inserted}`,
      `- updated:   ${stats.updated}`,
      `- deleted:   ${stats.deleted}`,
      `- unchanged: ${stats.unchanged}`,
    ].join("\n  ");
    console.log(`The following file changes were detected:\n  ${message}`);
    return true;
  } else {
    console.log(`No file changes were detected.`);
    return false;
  }
}

interface CommandOptions {
  modulesToInclude: string;
  targetVersion: string;
}
interface WorkerOptions {
  limitToModules?: string[];
}
function mapCommandToWorkerOptions(options: CommandOptions): WorkerOptions {
  return {
    limitToModules: options.modulesToInclude
      ? options.modulesToInclude.split(",")
      : undefined,
  };
}

const gen = async (
  input: string,
  outputPath: string,
  options: CommandOptions
) => {
  await fsMakeDir(outputPath, {
    recursive: true,
  });
  const morphirIrJson: Buffer = await fsReadFile(path.resolve(input)); // nosemgrep : path-join-resolve-traversal
  const workerOptions: WorkerOptions = mapCommandToWorkerOptions(options);
  // opts.limitToModules = options.modulesToInclude ? options.modulesToInclude.split(',') : undefined
  const generatedFiles: string[] = await generate(
    workerOptions,
    JSON.parse(morphirIrJson.toString())
  );

  const writePromises = generatedFiles.map(
    async ([[dirPath, fileName], content]: any) => {
      const fileDir: string = dirPath.reduce(
        (accum: string, next: string) => path.join(accum, next), // nosemgrep : path-join-resolve-traversal
        outputPath
      );
      const filePath: string = path.join(fileDir, fileName); // nosemgrep : path-join-resolve-traversal

      if (await fileExist(filePath)) {
        const existingContent: Buffer = await fsReadFile(filePath);

        if (existingContent.toString() !== content) {
          await fsWriteFile(filePath, content);
          console.log(`UPDATE - ${filePath}`);
        }
      } else {
        await fsMakeDir(fileDir, {
          recursive: true,
        });
        await fsWriteFile(filePath, content);
        console.log(`INSERT - ${filePath}`);
      }
    }
  );
  const filesToDelete = await findFilesToDelete(outputPath, generatedFiles);
  const deletePromises = filesToDelete.map(async (fileToDelete: string) => {
    console.log(`DELETE - ${fileToDelete}`);
    return fs.unlinkSync(fileToDelete); // nosemgrep : detect-non-literal-fs-filename
  });
  copyRedistributables(options, outputPath);
  return Promise.all(writePromises.concat(deletePromises));
};

const stats = async (
  input: string,
  outputPath: string,
  options: CommandOptions
) => {
  await fsMakeDir(outputPath, {
    recursive: true,
  });

  const collectStats = async (ir: string): Promise<string[]> => {
    return new Promise((resolve, reject) => {
      worker.ports.jsonDecodeError.subscribe((err: any) => {
        reject(err);
      });
      worker.ports.statsResult.subscribe(([err, ok]: any) => {
        if (err) {
          reject(err);
        } else {
          resolve(ok);
        }
      });

      worker.ports.stats.send(ir);
    });
  };

  const morphirIrJson: Buffer = await fsReadFile(path.resolve(input)); // nosemgrep : path-join-resolve-traversal

  const stats: string[] = await collectStats(
    JSON.parse(morphirIrJson.toString())
  );

  const writePromises = stats.map(
    async ([[dirPath, fileName], content]: any) => {
      const fileDir: string = dirPath.reduce(
        (accum: string, next: string) => path.join(accum, next), // nosemgrep : path-join-resolve-traversal
        outputPath
      );
      const filePath: string = path.join(fileDir, fileName); // nosemgrep : path-join-resolve-traversal

      if (await fileExist(filePath)) {
        const existingContent: Buffer = await fsReadFile(filePath);

        if (existingContent.toString() !== content) {
          await fsWriteFile(filePath, content);
          console.log(`UPDATE - ${filePath}`);
        }
      } else {
        await fsMakeDir(fileDir, {
          recursive: true,
        });
        await fsWriteFile(filePath, content);
        console.log(`INSERT - ${filePath}`);
      }
    }
  );
  return Promise.all(writePromises);
};

const generate = async (
  options: WorkerOptions,
  ir: string
): Promise<string[]> => {
  return new Promise((resolve, reject) => {
    worker.ports.jsonDecodeError.subscribe((err: any) => {
      reject(err);
    });
    worker.ports.generateResult.subscribe(([err, ok]: any) => {
      if (err) {
        reject(err);
      } else {
        resolve(ok);
      }
    });

    worker.ports.generate.send([options, ir]);
  });
};

const fileExist = async (filePath: string) => {
  return new Promise((resolve, reject) => {
    fs.access(filePath, fs.constants.F_OK, (err) => { // nosemgrep : detect-non-literal-fs-filename
      if (err) {
        resolve(false);
      } else {
        resolve(true);
      }
    });
  });
};

const findFilesToDelete = async (outputPath: string, fileMap: string[]) => {
  const readDir = async function (
    currentDir: string,
    generatedFiles: string[]
  ) {
    const entries: fs.Dirent[] = await readdir(currentDir, { // nosemgrep : detect-non-literal-fs-filename
      withFileTypes: true,
    });
    const filesToDelete = entries
      .filter((entry) => {
        const entryPath: string = path.join(currentDir, entry.name); // nosemgrep : path-join-resolve-traversal
        return entry.isFile() && !generatedFiles.includes(entryPath);
      })
      .map((entry) => path.join(currentDir, entry.name)); // nosemgrep : path-join-resolve-traversal
    const subDirFilesToDelete: Promise<string[]> = entries
      .filter((entry) => entry.isDirectory())
      .map((entry) =>
        readDir(path.join(currentDir, entry.name), generatedFiles) // nosemgrep : path-join-resolve-traversal
      )
      .reduce(async (soFarPromise, nextPromise) => {
        const soFar = await soFarPromise;
        const next = await nextPromise;
        return soFar.concat(next);
      }, Promise.resolve([]));
    return filesToDelete.concat(await subDirFilesToDelete);
  };
  const files = fileMap.map(([[dirPath, fileName], content]: any) => {
    const fileDir = dirPath.reduce(
      (accum: string, next: string) => path.join(accum, next), // nosemgrep : path-join-resolve-traversal
      outputPath
    );
    return path.resolve(fileDir, fileName); // nosemgrep : path-join-resolve-traversal
  });
  return Promise.all(await readDir(outputPath, files));
};

function copyRedistributables(options: CommandOptions, outputPath: string) {
  const copyFiles = (src: string, dest: string) => {
    const sourceDirectory: string = path.join(
      path.dirname(__dirname),
      "redistributable",
      src // nosemgrep : path-join-resolve-traversal
    );
    copyRecursiveSync(sourceDirectory, outputPath);
  };
  copyFiles("Scala/sdk/src", outputPath);
  copyFiles(`Scala/sdk/src-${options.targetVersion}`, outputPath);
}

function copyRecursiveSync(src: string, dest: string) {
  const exists = fs.existsSync(src); // nosemgrep : detect-non-literal-fs-filename
  if (exists) {
    const stats = exists && fs.statSync(src); // nosemgrep : detect-non-literal-fs-filename
    const isDirectory = exists && stats.isDirectory();
    if (isDirectory) {
      if (!fs.existsSync(dest)) fs.mkdirSync(dest); // nosemgrep : detect-non-literal-fs-filename
      fs.readdirSync(src).forEach(function (childItemName) { // nosemgrep : detect-non-literal-fs-filename
        copyRecursiveSync(
          path.join(src, childItemName), // nosemgrep : path-join-resolve-traversal
          path.join(dest, childItemName) // nosemgrep : path-join-resolve-traversal
        );
      });
    } else {
      fs.copyFileSync(src, dest); // nosemgrep : detect-non-literal-fs-filename
      console.log(`COPY - ${dest}`);
    }
  }
}

async function writeFile(filePath: string, content: string) {
  await fsMakeDir(path.dirname(filePath), {
    recursive: true,
  });
  return await fsWriteFile(filePath, content);
}


async function writeDockerfile(
  projectDir: string,
  programOpts: any
): Promise<void> {
  // read docker template file
  let filePath = "./cli2/DockerTemplateFile"
  let fileContent = await fsReadFile(filePath, 'utf-8')  

  // replace specific characteres with the required 
  let newContent = fileContent.replace("PROJECT_MODEL_DIR", projectDir.replace(/\\/g, '/'))


  // controlling ending slash in path
  let removeTrailingSlash = (str: string) => { return str.endsWith('/') ? str.slice(0, -1).trim() : str.trim() };
  let dockerfilePath = removeTrailingSlash(projectDir + "/Dockerfile")


  // check if there is an existing Dockerfile in projectDir
  if (await fsExists(dockerfilePath) && programOpts.force == false) {
    throw new Error("Dockerfile already exist. To overwrite please use the `-f` flag");
  }
  else  {
    await fsWriteFile(dockerfilePath, newContent)
  }
}

export = { make, writeFile, gen, stats, writeDockerfile };

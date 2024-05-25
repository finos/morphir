#!/usr/bin/env node

import * as fs from "fs";
import * as util from "util";
import * as path from "path";
import * as FileChanges from "./FileChanges";
import * as Dependencies from "./dependencies";
import { DependencyConfig } from "./dependencies";
import { z } from "zod";

const fsExists = util.promisify(fs.exists);
const fsWriteFile = util.promisify(fs.writeFile);
const fsMakeDir = util.promisify(fs.mkdir);
const fsReadFile = util.promisify(fs.readFile);
const readdir = util.promisify(fs.readdir);

const worker = require("./../Morphir.Elm.CLI").Elm.Morphir.Elm.CLI.init();

const Includes = z.array(z.string()).optional();
type Includes = z.infer<typeof Includes>;

interface MorphirJson {
  name: string;
  sourceDirectory: string;
  dependencies?: string[];
  localDependencies?: string[];
  exposedModules: string[];
}

async function make(
  projectDir: string,
  options: any
): Promise<string | undefined> {
  // Morphir specific files expected to be in the project directory
  const morphirJsonPath: string = path.join(projectDir, "morphir.json");
  const hashFilePath: string = path.join(projectDir, "morphir-hashes.json");
  const morphirIrPath: string = path.join(projectDir, "morphir-ir.json");


  // Load the `morphir.json` file that describes the project
  const morphirJson: MorphirJson = JSON.parse(
    (await fsReadFile(morphirJsonPath)).toString()
  );

  const includes = Includes.parse(options.include);
  const dependencyConfig = DependencyConfig.parse({
    dependencies: morphirJson.dependencies,
    localDependencies: morphirJson.localDependencies,
    includes: includes
  })

  //load List Of Dependency IR
  const dependencies = await Dependencies.loadAllDependencies(dependencyConfig);

  // check the status of the build incremental flag
  if (options.buildIncrementally == false) {
    // We invoke file change detection but pass in no hashes which will generate inserts only
    const fileChanges = await FileChanges.detectChanges(
      new Map(),
      path.join(projectDir, morphirJson.sourceDirectory)
    );

    const fileSnapshot = FileChanges.toFileSnapshotJson(fileChanges);
    const newIR: string = await buildFromScratch(
      morphirJson,
      fileSnapshot,
      dependencies,
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
        path.join(projectDir, morphirJson.sourceDirectory)
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
          dependencies,
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
        path.join(projectDir, morphirJson.sourceDirectory)
      );
      const fileSnapshot = FileChanges.toFileSnapshotJson(fileChanges);
      const newIR: string = await buildFromScratch(
        morphirJson,
        fileSnapshot,
        dependencies,
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
  dependencies: string[],
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
        resolve(JSON.stringify(ok, null, options.indentJson ? 4 : 0));
      }
    });

    const opts = {
      typesOnly: options.typesOnly,
    };

    worker.ports.buildFromScratch.send({
      options: opts,
      packageInfo: morphirJson,
      dependencies: dependencies,
      fileSnapshot: fileSnapshot,
    });
  });
}

async function buildIncrementally(
  morphirJson: any,
  fileChanges: FileChanges.FileChanges,
  options: any,
  dependencies: string[],
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
        resolve(JSON.stringify(ok, null, options.indentJson ? 4 : 0));
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
      dependencies: dependencies,
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
  await writeFile(filePath, JSON.stringify(jsonObject, null, 4));
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
  limitToModules: string;
  targetVersion: string;
  includeCodecs: boolean;
}

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

  const morphirIrJson: Buffer = await fsReadFile(path.resolve(input));

  const stats: string[] = await collectStats(
    JSON.parse(morphirIrJson.toString())
  );

  const writePromises = stats.map(
    async ([[dirPath, fileName], content]: any) => {
      const fileDir: string = dirPath.reduce(
        (accum: string, next: string) => path.join(accum, next),
        outputPath
      );
      const filePath: string = path.join(fileDir, fileName);

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

const fileExist = async (filePath: string) => {
  return new Promise((resolve, reject) => {
    fs.access(filePath, fs.constants.F_OK, (err) => {
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
    const entries: fs.Dirent[] = await readdir(currentDir, {
      withFileTypes: true,
    });
    const filesToDelete = entries
      .filter((entry) => {
        const entryPath: string = path.join(currentDir, entry.name);
        return entry.isFile() && !generatedFiles.includes(entryPath);
      })
      .map((entry) => path.join(currentDir, entry.name));
    const subDirFilesToDelete: Promise<string[]> = entries
      .filter((entry) => entry.isDirectory())
      .map((entry) =>
        readDir(path.join(currentDir, entry.name), generatedFiles)
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
      (accum: string, next: string) => path.join(accum, next),
      outputPath
    );
    return path.resolve(fileDir, fileName);
  });
  return Promise.all(await readDir(outputPath, files));
};

function copyRedistributables(options: CommandOptions, outputPath: string) {
  const copyFiles = (src: string, dest: string) => {
    const sourceDirectory: string = path.join(
      path.dirname(__dirname),
      "redistributable",
      src
    );
    copyRecursiveSync(sourceDirectory, outputPath);
  };
  copyFiles("Scala/sdk/src", outputPath);
  copyFiles(`Scala/sdk/src-${options.targetVersion}`, outputPath);
}

function copyRecursiveSync(src: string, dest: string) {
  const exists = fs.existsSync(src);
  if (exists) {
    const stats = exists && fs.statSync(src);
    const isDirectory = exists && stats.isDirectory();
    if (isDirectory) {
      if (!fs.existsSync(dest)) fs.mkdirSync(dest);
      fs.readdirSync(src).forEach(function (childItemName) {
        copyRecursiveSync(
          path.join(src, childItemName),
          path.join(dest, childItemName)
        );
      });
    } else {
      fs.copyFileSync(src, dest);
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

const generate = async (options: any, ir: string): Promise<string[]> => {
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

    worker.ports.generate.send([options, ir, []]);
  });
};

const gen = async (input: string, outputPath: string, options: any) => {
  await fsMakeDir(outputPath, {
    recursive: true,
  });
  const morphirIrJson: Buffer = await fsReadFile(path.resolve(input));

  const generatedFiles: string[] = await generate(
    options,
    JSON.parse(morphirIrJson.toString())
  );

  const writePromises = generatedFiles.map(
    async ([[dirPath, fileName], content]: any) => {
      const fileDir: string = dirPath.reduce(
        (accum: string, next: string) => path.join(accum, next),
        outputPath
      );
      const filePath: string = path.join(fileDir, fileName);

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
    return fs.unlinkSync(fileToDelete);
  });
  return Promise.all(writePromises.concat(deletePromises));
};

async function writeDockerfile(
  projectDir: string,
  programOpts: any
): Promise<void> {
  // read docker template file
  let filePath = "./cli2/DockerTemplateFile";
  let fileContent = await fsReadFile(filePath, "utf-8");

  // replace specific characteres with the required
  let newContent = fileContent.replace(
    "PROJECT_MODEL_DIR",
    projectDir.replace(/\\/g, "/")
  );

  // controlling ending slash in path
  let removeTrailingSlash = (str: string) => {
    return str.endsWith("/") ? str.slice(0, -1).trim() : str.trim();
  };
  let dockerfilePath = removeTrailingSlash(projectDir + "/Dockerfile");

  // check if there is an existing Dockerfile in projectDir
  if ((await fsExists(dockerfilePath)) && programOpts.force == false) {
    throw new Error(
      "Dockerfile already exist. To overwrite please use the `-f` flag"
    );
  } else {
    await fsWriteFile(dockerfilePath, newContent);
  }
}

async function testCoverage(
  irPath: string,
  testsPath: string,
  outputPath: string,
  options: CommandOptions
) {
  // Morphir IR
  const morphirIR: Buffer = await fsReadFile(path.resolve(irPath))
  const morphirIRJson: JSON = JSON.parse(morphirIR.toString())

  // read Morphir Test
  const morphirTest: Buffer = await fsReadFile(path.resolve(testsPath))
  const morphirTestJson: JSON = JSON.parse(morphirTest.toString())

  // output path 
  const output = path.join(path.resolve(outputPath), "morphir-test-coverage.json")

  return new Promise((resolve, reject) => {
    worker.ports.testCoverageResult.subscribe(([err, data]: any) => {
      if (err) {
        reject(err)
      }
      else {
        resolve(data)
      }
    })

    // send files through port
    worker.ports.testCoverage.send([morphirIRJson, morphirTestJson])
  });
}

export = {
  gen,
  make,
  writeFile,
  fileExist,
  stats,
  writeDockerfile,
  findFilesToDelete,
  copyRedistributables,
  testCoverage,
  worker,
};

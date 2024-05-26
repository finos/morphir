#!/usr/bin/env node

// NPM imports
import * as fs from "fs";
import path from "path";
import { Command } from "commander";
import * as util from "util";
import cli from "./cli";
import CLI from "./elm/Morphir/Elm/CLI.elm";

const fsWriteFile = util.promisify(fs.writeFile);
const fsMakeDir = util.promisify(fs.mkdir);
const fsReadFile = util.promisify(fs.readFile);

const worker = CLI.init();

interface CommandOptions {
  /**
   *  Name of the decorations file to load
   */
  decorations?: string;

  /**
   *  Internal property used to send the contents of the decorations file to the Elm code.
   */
  decorationsObj?: Array<{ [key: string]: Array<string> }>;
  limitToModules?: string;
  includeCodecs?: boolean;
  target?: string;
}

function copyRedistributables(outputPath: string) {
  const copyFiles = (src: string, _dest: string) => {
    const sourceDirectory: string = path.join(
      path.dirname(__dirname),
      "redistributable",
      src
    );
    if (fs.existsSync(sourceDirectory)) {
      fs.cpSync(sourceDirectory, outputPath, {
        recursive: true,
        errorOnExist: false,
      });
    } else {
      console.warn(`WARNING: Cannot find directory ${sourceDirectory}`);
    }
  };
  copyFiles("Snowpark", outputPath);
}

const generate = async (
  options: CommandOptions,
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

    worker.ports.generate.send([options, ir, []]);
  });
};

const gen = async (
  input: string,
  outputPath: string,
  options: CommandOptions
) => {
  await fsMakeDir(outputPath, {
    recursive: true,
  });

  // Add default values for these options
  options.limitToModules = "";
  options.includeCodecs = false;
  options.target = "Snowpark";

  if (options.decorations) {
    if (fs.existsSync(path.resolve(options.decorations))) {
      let fileContents = await fsReadFile(path.resolve(options.decorations));
      options.decorationsObj = JSON.parse(fileContents.toString());
    } else {
      console.warn(
        `WARNING: The specified decorations file do not exist: ${options.decorations}`
      );
    }
  }

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

      if (await cli.fileExist(filePath)) {
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
  const filesToDelete = await cli.findFilesToDelete(outputPath, generatedFiles);
  const deletePromises = filesToDelete.map(async (fileToDelete: string) => {
    console.log(`DELETE - ${fileToDelete}`);
    return fs.unlinkSync(fileToDelete);
  });
  copyRedistributables(outputPath);
  return Promise.all(writePromises.concat(deletePromises));
};

export const command = new Command();
command
  .name("snowpark-gen")
  .description("Generate Scala with Snowpark code from Morphir IR")
  .option(
    "-i, --input <path>",
    "Source location where the Morphir IR will be loaded from.",
    "morphir-ir.json"
  )
  .option(
    "-o, --output <path>",
    "Target location where the generated code will be saved.",
    "./dist"
  )
  .option("-dec, --decorations <filename>", "JSON file with decorations")
  .action(run);

async function run(options: { input: string; output: string }) {
  return await gen(options.input, path.resolve(options.output), command.opts())
    .then(() => {
      console.log("Done");
    })
    .catch((err) => {
      console.log(err);
      process.exit(1);
    });
}

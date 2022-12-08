#!/usr/bin/env node

// NPM imports
import * as fs from "fs";
import { Command } from 'commander';
import path from 'path';
import * as util from "util";

import cli from './cli';

const fsWriteFile = util.promisify(fs.writeFile);
const fsMakeDir = util.promisify(fs.mkdir);
const fsReadFile = util.promisify(fs.readFile);

const worker = require("./../Morphir.Elm.CLI").Elm.Morphir.Elm.CLI.init();


require('log-timestamp')

interface CommandOptions {
  limitToModules: string;
  filename: string; 
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
  
      worker.ports.generate.send([options, ir]);
    });
  };

const gen = async (
    input: string,
    outputPath: string,
    options: CommandOptions
  ) => {
    console.log(options)
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
    return Promise.all(writePromises.concat(deletePromises));
  };
  

const program = new Command
program
    .name('morphir json-schema-gen')
    .description('Generate Json Schema from Morphir IR')
    .option('-i, --input <path>', 'Source location where the Morphir IR will be loaded from.', 'morphir-ir.json')
    .option('-o, --output <path>', 'Target location where the generated code will be saved.', './dist')
    .option('-t, --target <type>', 'Language to Generate. It would always be JsonSchema', 'JsonSchema')
    .option('-e, --target-version <version>', 'Language version to Generate.', '2.11')
    .option('-c, --copy-deps', 'Copy the dependencies used by the generated code to the output path.', false)
    .option('-f, --filename <filename>', 'Filename of the generated JSON Schema.', '')
    .option('-m, --limit-to-modules <comma.separated,list.of,module.names>', 'Limit the set of modules that will be included.', '')
    .option('-cc, --custom-config <filepath>', 'A filepath to load additional configuration for the backend.')
    .parse(process.argv)

    gen(program.opts().input, path.resolve(program.opts().output), program.opts())
        .then(() => {
            console.log("Done")
        })
        .catch((err) => {
            console.log(err);
            process.exit(1)
        })


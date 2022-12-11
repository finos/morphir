/*
This file serves as the entrypoint for Json Schema Backend configuration processing
*/
import * as fs from "fs";
import path from 'path';
import * as util from 'util'
const fsReadFile = util.promisify(fs.readFile);

const configFilePath: string = "JsonSchema.config.json";

// Interface for JsonSchema backend opitons
interface JsonBackendOptions {
      input: string,
      output: string,
      targetVersion : string,
      filename: string,
      useConfig: boolean,
      limitToModules : string[],
      groupBy: string
}

/*
This function determines the Json Schema code generation parameters based on
- cli defaults
- cli user options
- config if if it exists
*/
async function inferBackendConfig(cliOptions: any):Promise<JsonBackendOptions>{
    let selectedOptions: JsonBackendOptions = {
        input: "",
        output: "",
        targetVersion: "",
        filename: "",
        useConfig: false,
        limitToModules: [],
        groupBy: ""
    }
    if (cliOptions.useConfig){ //then use the config file parameters
        const configFileBuffer: Buffer = await fsReadFile(path.resolve(configFilePath));
        const configFileJson = JSON.parse(configFileBuffer.toString());

        // Check if content of config file have changed,
        if (configFileJson != cliOptions) { 
            selectedOptions.input = cliOptions.input == configFileJson.input? cliOptions.input : configFileJson.input
            selectedOptions.output = cliOptions.input == configFileJson.input? cliOptions.input : configFileJson.input
            selectedOptions.targetVersion = cliOptions.targetVersion == configFileJson.targetVersion? cliOptions.targetVersion : configFileJson.targetVersion
            selectedOptions.useConfig = cliOptions.useConfig == configFileJson.useConfig? cliOptions.useConfig : configFileJson.useConfig         
            selectedOptions.limitToModules = cliOptions.limitToModules == configFileJson.limitToModules? cliOptions.limitToModules : configFileJson.limitToModules
            selectedOptions.groupBy = cliOptions.groupBy == configFileJson.groupBy? cliOptions.groupBy : configFileJson.groupBy
        }
        else {
            selectedOptions = configFileJson
        }
    }
    else { // Use the cli command defaults
        selectedOptions = cliOptions
    }
    return selectedOptions
}

export = {inferBackendConfig}
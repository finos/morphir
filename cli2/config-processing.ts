/*
This file serves as the entrypoint for Json Schema Backend configuration processing
*/
import * as fs from "fs";
import path from 'path';
import * as util from 'util'
import cli from "./cli";

const fsReadFile = util.promisify(fs.readFile);
const configFilePath: string = "JsonSchema.config.json";

// Interface for JsonSchema backend opitons
export interface JsonBackendOptions {
      input: string,
      output: string,
      target: string,
      targetVersion : string,
      filename: string,
      useConfig: boolean,
      limitToModules : any,
      groupSchemaBy: string
}

/*
This function determines the Json Schema code generation parameters based on
- cli defaults
- cli user options
- config if if it exists
The algorithm is given below:

def inferBackenConfig:
    initialize workerOptions/selectedOptions with empty fields
    if use-Config exists then:
    read content of config file
    if configFile != cliOptions
            for each config parameter
                Check if user explicitly specified a paramter
                    set the workerOptions field with the parameter
                else:
                    set the workerOptions field with config file  field
        else:
            set workerOptions = configFile
    else:
        set workerOptions = cliOptions
    return workerOptions

*/
async function inferBackendConfig(cliOptions: any):Promise<JsonBackendOptions>{
   
    let selectedOptions: JsonBackendOptions = {
        input: "",
        output: "",
        targetVersion: "",
        filename: "",
        useConfig: false,
        limitToModules: [],
        groupSchemaBy: "",
        target: "JsonSchema"
    }

    if (cliOptions.useConfig){ //then use the config file parameters
        const configFileBuffer:Buffer =  await fsReadFile(path.resolve(configFilePath));
        const configFileJson = JSON.parse(configFileBuffer.toString());

        // Check if content of config file have changed,
        if (configFileJson != cliOptions) {
            selectedOptions.input = cliOptions.input != "morphir-ir.json"? cliOptions.input : configFileJson.input
            selectedOptions.output = cliOptions.input != "./dist"? cliOptions.output : configFileJson.output
            selectedOptions.targetVersion = cliOptions.targetVersion != "2020-12"? cliOptions.targetVersion : configFileJson.targetVersion
            selectedOptions.useConfig = cliOptions.useConfig != false? cliOptions.useConfig : configFileJson.useConfig         
            selectedOptions.limitToModules = cliOptions.limitToModules != ""? cliOptions.limitToModules : configFileJson.limitToModules.split(",")
            selectedOptions.filename = cliOptions.filename != ""? cliOptions.filename : configFileJson.filename
            selectedOptions.groupSchemaBy = cliOptions.groupSchemaBy != "package"? cliOptions.groupSchemaBy : configFileJson.groupSchemaBy
        }
        else {
            selectedOptions = configFileJson
        }
    }
    else { // Process and use the cli defaults except where a parameter was specified in a flag
        selectedOptions = cliOptions
        selectedOptions.limitToModules = cliOptions.limitToModules? cliOptions.limitToModules.split(" "): []
    }
    return selectedOptions
}

export default {inferBackendConfig}
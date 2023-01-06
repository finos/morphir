/*
This file serves as the entrypoint for Json Schema Backend configuration processing
*/
import * as fs from "fs";
import * as path from 'path';
import * as util from 'util'
import cli from "./cli";

const fsReadFile = util.promisify(fs.readFile);
const configFilePath: string = "JsonSchema.config.json";
const attributesFilePath:string = "attributes/json-schema-enabled.json"

// Interface for JsonSchema backend opitons
export interface JsonBackendOptions {
      input: string,
      output: string,
      target: string,
      targetVersion : string,
      filename: string,
      limitToModules : any,
      groupSchemaBy: string,
      include: any,
      useDecorators: boolean
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

// Function to read the list of types from the custom attributes file
async function getTypesFromCustomAttributes(){
    const attributesBuffer:Buffer =  await fsReadFile(path.resolve(attributesFilePath));
    const attributesJson = JSON.parse(attributesBuffer.toString());

    Object.keys(attributesJson).forEach((key:any) => {
      if (!attributesJson[key]) delete attributesJson[key];
    });

    const attributesFiltered = Object.keys(attributesJson)
    const typeNames = attributesFiltered.map(attrib => attrib.split(":").slice(-2).join(".") )
    return typeNames
}

async function inferBackendConfig(cliOptions: any):Promise<JsonBackendOptions>{
    getTypesFromCustomAttributes();
    let selectedOptions: JsonBackendOptions = {
        input: "",
        output: "",
        targetVersion: "",
        filename: "",
        limitToModules: null,
        groupSchemaBy: "",
        target: "JsonSchema",
        include: null,
        useDecorators: false
    }

    if (cliOptions.useConfig) { //then use the config file parameters
        const configFileBuffer:Buffer =  await fsReadFile(path.resolve(configFilePath));
        const configFileJson = JSON.parse(configFileBuffer.toString());

        // Check if content of config file have changed,
        if (configFileJson != cliOptions) {
            selectedOptions.targetVersion = cliOptions.targetVersion != "2020-12"? cliOptions.targetVersion : configFileJson.targetVersion
            selectedOptions.limitToModules = cliOptions.limitToModules != ""? cliOptions.limitToModules : configFileJson.limitToModules.split(",")
            selectedOptions.filename = cliOptions.filename != ""? cliOptions.filename : configFileJson.filename
            selectedOptions.groupSchemaBy = cliOptions.groupSchemaBy != "package"? cliOptions.groupSchemaBy : configFileJson.groupSchemaBy
            if (cliOptions.include) {
                selectedOptions.include = cliOptions.include
            } else {
                selectedOptions.include = configFileJson.include != ""? configFileJson.include.split(",") : ""
            }
            if (cliOptions.useDecorators){
                cliOptions.include = getTypesFromCustomAttributes()
            }
        }
        else {
            selectedOptions = configFileJson
            if (cliOptions.useDecorators){
                cliOptions.include = getTypesFromCustomAttributes()
            }
        }
    }
    else { // Process and use the cli defaults except where a parameter was specified in a flag
        selectedOptions = cliOptions
        selectedOptions.limitToModules = cliOptions.limitToModules? cliOptions.limitToModules.split(" "): ""
        selectedOptions.include = cliOptions.include? cliOptions.include.split(" "): ""
        if (cliOptions.useDecorators){
            cliOptions.include = await getTypesFromCustomAttributes()
        }
    }
    return selectedOptions
}

export default {inferBackendConfig}
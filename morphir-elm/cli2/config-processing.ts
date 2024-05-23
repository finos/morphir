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
      target: string,  //Required by the Target elm module
      targetVersion : string,
      filename: string,
      limitToModules : any,
      groupSchemaBy: string,
      include: any,
      useDecorators: boolean
}

// Function to read the list of module or types from the custom attributes file
async function getNamesFromCustomAttributes(){
    const attributesBuffer:Buffer =  await fsReadFile(attributesFilePath);
    const attributesJson = JSON.parse(attributesBuffer.toString());

    //Remove attributes where the value is false
    Object.keys(attributesJson).forEach((key:any) => {
      if (!attributesJson[key]) delete attributesJson[key];
    });

    //Get all the Fully Type Names ie Value:TestModel:OptionalTypes:assignment -> OptionalType.Assignments
    const attributesFiltered = Object.keys(attributesJson)
    const moduleOrTypeNames = attributesFiltered.map(attrib =>
        (attrib.substring(0,6) == "Module" ) ?  attrib.split(":").slice(-1).join("") : attrib.split(":").slice(-2).join(".") )
    return moduleOrTypeNames
}

/*
    Function to determine what configuration flags to use based on the following:
    - if useConfig flag is set, then read configuration from the JsonSchema.config.json file
    - if useDecorator is set, then set the value of the include using types from useDecorators
    - if a specific flag is manually set in the cli, then that specific flag is used
    - if no flag is set, then use the commander defaults
*/
async function inferBackendConfig(cliOptions: any):Promise<JsonBackendOptions>{
    let selectedOptions: JsonBackendOptions = {
        input: "",
        output: "",
        target: "JsonSchema",  //Required by the Target elm module
        targetVersion: "",
        filename: "",
        limitToModules: null,
        groupSchemaBy: "",
        include: null,
        useDecorators: false
    }

    if (cliOptions.useConfig) { //then use the config file parameters
        const configFileBuffer:Buffer =  await fsReadFile(path.resolve(configFilePath));
        const configFileJson = JSON.parse(configFileBuffer.toString());

        // Check if content of config file have changed ie. it's values are not the defaults
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
                cliOptions.include = getNamesFromCustomAttributes()
            }
        }
        //Else, config file has not changed, it still contains the defaults
        else {
            selectedOptions = configFileJson
            if (cliOptions.useDecorators){
                cliOptions.include = getNamesFromCustomAttributes()
            }
        }
    }
    else { // Process and use the cli defaults except where a parameter was specified in a flag
        selectedOptions = cliOptions
        selectedOptions.limitToModules = cliOptions.limitToModules? cliOptions.limitToModules.split(" "): ""
        selectedOptions.include = cliOptions.include? cliOptions.include.split(" "): ""

        // Get types to include from Decorators if useDecorators is set
        if (cliOptions.useDecorators){
            cliOptions.include = await getNamesFromCustomAttributes()
        }
    }
    return selectedOptions
}

export default {inferBackendConfig}
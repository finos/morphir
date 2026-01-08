---
id: generating-json-schema
sidebar_position: 2
---

# Generating a JSON Schema
This document explains how to generate a JSON Schema. It covers how to specify code generation parameters via 
commandline, configuration file and the Develop UI.
**Note**: To generate a Json Schema, you have an existing IR.

## 1. CommandLine
Run the command 
`morphir json-schema-gen`
You can specify any optional flags, otherwise, the default values are used.

## 2. Configuration File
To use a configuration file, you must have created a configuration file named JsonSchema.config.json.
This file would contain parameters which would otherwise have been specified as command-line flags.
An example of configuration file content is given below:
```json
{
  "targetVersion": "2020-12",
  "filename": "",
  "limitToModules": "",
  "groupSchemaBy": "module",
  "target": "JsonSchema",
  "include": "BasicTypes,AdvancedTypes,OptionalTypes"
}

```
To create a Json Schema based on the configuration file, you would use the command below:
`morphir json-schema-gen -c true`

## 3. Develop UI
The Decorator feature in Morphir allows you to specify what to include (Modules and/or Type) in the generated schema via the Develop UI.
To use the Develop UI, follow the steps:
1. start the Develop UI
2. select a module or type
3. click on the Custom Attributes  tab
4. set the Custom attribute option to "Yes"
5. Repeat steps 2 to 4 for all the types/modules you want to include
6. Then on the command line, run the morphir json-schema-gen command with the -d flag set to true as shown below:
`morphir json-schema-gen -d true`

**Node**: You can also manually specify additional command line  flag as well.
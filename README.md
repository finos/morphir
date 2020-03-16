# morphir-elm

[![npm version](https://badge.fury.io/js/morphir-elm.svg)](https://badge.fury.io/js/morphir-elm)

morphir-elm is a set of tools to work with Morphir in Elm. It currently provides these features: 

* Translate Elm sources to Morphir IR
* Generate code from the Morphir IR

# Installation

```
npm install -g morphir-elm
```

# Usage

All the features can be accessed through sub-commands within the `morphir-elm` command:

```
morphir-elm [command]
```

Each command has different options which are detailed below:

## Translate Elm sources to Morphir IR

This command reads Elm sources, translates to Morphir IR and outputs the IR into JSON. 

```
morphir-elm make [options]
```

**Important**: The command requires a configuration file called `morphir.json` located in the project 
root directory with the following structure:

```
{
    "name": "package-name",
    "sourceDirectory": "src",
    "exposedModules": [
        "Foo",
        "Bar"
    ]
}
```

### Options

|Option|Shorthand|Description|
|---|---|---|
|`--project-dir <path>`|`-p`|Root directory of the project where morphir.json is located. (default: ".")|
|`--output <path>`|`-o`|Target location where the Morphir IR will be sent. Defaults to STDOUT.|

## Generate code from the Morphir IR 

Generate code from the Morphir IR

```
morphir-elm gen
```
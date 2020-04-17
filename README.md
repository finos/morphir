# morphir-elm

[![npm version](https://badge.fury.io/js/morphir-elm.svg)](https://badge.fury.io/js/morphir-elm)

morphir-elm is a set of tools to work with Morphir in Elm. It currently provides these features: 

* Translate Elm sources to Morphir IR
* Model stateful Dapr applications in elm

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

## Generate Dapr application

This command reads Elm source code to generate [Dapr]((https://dapr.io)) applications

**Important**: Requires [elm-platform 0.19.1]((https://guide.elm-lang.org/install/elm.html)) to be available locally.

```
morphir-dapr -p <path/to/morphir-dapr.json> -o <path/to/dapr/output>
```

Following is an example of a `morphir-dapr.json` configuration file

```
{
    "name": "Morphir/Dapr/Input",
    "sourceDirectories": ["examples"],
    "exposedModules": [
        "Example"
    ]
}
```

### Options

|Option|Shorthand|Description|
|---|---|---|
|`--project-dir <path>`|`-p`|Root directory of the project where morphir-dapr.json is located. (default: ".")|
|`--output <path>`|`-o`|Target location where the Dapr sources will be sent. Will create it if it does not exist (default: "dapr-output")|
|`--info`|`-i`|Print dapr intermediate output (elm) to STDOUT|
|`--delete`|`-d`|Delete build directory|


### Deploying Dapr Applications

[Dapr Docs](https://github.com/dapr/docs)

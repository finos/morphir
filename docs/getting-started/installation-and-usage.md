---
id: installation-and-usage
sidebar_position: 3
---

#Morphir Tools 

Morphir is provided as a set of command-line tools that are distribution through the NPM packaging system.
The current version is:

[![npm version](https://badge.fury.io/js/morphir-elm.svg)](https://badge.fury.io/js/morphir-elm)

## Installation
To install morphir, use the standard NPM installation commands:
```
npm install -g morphir-elm
```

## Usage

All the features can be accessed through sub-commands within the `morphir-elm` command:

```
Usage: morphir-elm [options] [command]

Options:
  -v, --version  output the version number
  -h, --help     output usage information

Commands:
  make           Translate Elm sources to Morphir IR
  gen            Generate code from Morphir IR
  develop        Start up a web server and expose developer tools through a web UI
  help [cmd]     display help for [cmd]
```

Each command has different options which are detailed below:

### `morphir-elm make`

This command reads Elm sources, translates to Morphir IR and outputs the IR into JSON.

```
Usage: morphir-elm make [options]

Translate Elm sources to Morphir IR

Options:
  -p, --project-dir <path>  Root directory of the project where morphir.json is located. (default: ".")
  -o, --output <path>       Target file location where the Morphir IR will be saved. (default: "morphir-ir.json")
  -h, --help                output usage information
```

**Important**: The command requires a configuration file called `morphir.json` located in the project
root directory with the following structure:

```
{
    "name": "My.Package",
    "sourceDirectory": "src",
    "exposedModules": [
        "Foo",
        "Bar"
    ]
}
```

* **name** - The name of the package. The package name should be a valid Elm module name and it should be used as a
  module prefix in your Elm models. If your package name is `My.Package` all your module files should either be directly
  under that or in submodules.
* **sourceDirectory** - The directory where your Elm sources are located.
* **exposedModules** - The list of modules in the public interface of the package. Module names should exclude the
  common package prefix. In the above example `Foo` refers to the Elm module `My.Package.Foo`.

#### Examples

If you want to try the `make` command you can use the reference model we have under `tests-integration/reference-model`. Simply `cd` into the directory and run the command.

### `morphir-elm gen`

This command reads the JSON produced by `morphir-elm make` and generates code into the specified folder:

```
Usage: morphir-elm gen [options]

Generate code from Morphir IR

Options:
  -i, --input <path>              Source location where the Morphir IR will be loaded from. (default: "morphir-ir.json")
  -o, --output <path>             Target location where the generated code will be saved. (default: "./dist")
  -t, --target <type>             Language to Generate (Scala | SpringBoot | cypher | triples). (default: "Scala")
  -e, --target-version <version>  Language version to Generate. (default: "2.11")
  -c, --copy-deps                 Copy the dependencies used by the generated code to the output path. (default: false)
  -h, --help                      output usage information
```

#### Examples

If you want to try the `gen` command you can use the reference model we have under `tests-integration/reference-model`. Simply `cd` into the directory and run the command.

### `morphir-elm develop`

This command relies on the JSON produced by `morphir-elm make` and brings up a web server to browse the Morphir IR.

```
Usage: morphir-elm develop [options]

Start up a web server and expose developer tools through a web UI

Options:
  -p, --project-dir <path>  Root directory of the project where morphir.json is located. (default: ".")
  -h, --help                output usage information
```

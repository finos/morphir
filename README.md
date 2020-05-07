# morphir-elm


morphir-elm is a set of tools to work with Morphir in Elm. It's dual published as an NPM and an Elm package:

- NPM package: [![npm version](https://badge.fury.io/js/morphir-elm.svg)](https://badge.fury.io/js/morphir-elm)
- Elm package: ![Latest version of the Elm package](https://reiner-dolp.github.io/elm-badges/Morgan-Stanley/morphir-elm/version.svg)
 
The NPM package provides a CLI to run the tooling while the Elm package can be used for direct integration. 
The CLI currently supports the following features:  

- [Translate Elm sources to Morphir IR](#translate-elm-sources-to-morphir-ir)

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

- `--project-dir <path>`, `-p`
  - Root directory of the project where morphir.json is located. 
  - Defaults to current directory.
- `--output <path>`, `-o`
  - Target location where the Morphir IR will be sent
  - Defaults to STDOUT.

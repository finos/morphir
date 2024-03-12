# morphir-elm
![morphir-elm](docs/assets/2020_Morphir_Logo_Horizontal.svg)

[Morphir](https://github.com/finos/morphir) is a multi-language system built on a data format that captures an 
application's domain model and business logic in a technology agnostic manner. This repo contains tools that
allow you to write your business logic in [Elm](https://elm-lang.org/), parse it into Morphir IR and transpile 
it to other languages like [Scala](https://www.scala-lang.org/) or visualize it to your business users using Elm.

We publish it both as an NPM and an Elm package:

![Package Overview](docs/assets/package-overview.png)

- The [NPM package](#npm-package) contains the CLI for running the tools as part of your build.
- The [Elm package](#elm-package) supports multiple use-cases:
  - It includes SDK functions that you can use while writing your business logic beyond the default `elm/core` support.
  - It provides a type-safe API to work with the Morphir IR directly. You can use this to add your own logic builder, 
  visualization or language transpiler.
  - It also provides access to the frontend that parses the Elm source code and returns Morphir IR. You could use this 
  to embed a business logic editor in your web UI. 

# NPM package

[![npm version](https://badge.fury.io/js/morphir-elm.svg)](https://badge.fury.io/js/morphir-elm)
 
The **morphir-elm** NPM package provides a CLI to run the tooling. 

## Installation

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

#### Examples

If you want to try the `develop` server you can use the reference model we have under `tests-integration/reference-model`. Simply `cd` into the directory and run the command.


# Elm package

[![Latest version of the Elm package](https://reiner-dolp.github.io/elm-badges/finos/morphir-elm/version.svg)](https://package.elm-lang.org/packages/finos/morphir-elm/latest)

The [finos/morphir-elm](https://package.elm-lang.org/packages/finos/morphir-elm/latest) package 
provides various tools to work with Morphir. It contains the following main components:

- The [Morphir SDK](#morphir-sdk) which provides the base set of types and functions that Morphir tools support 
  out-of-the-box. (the SDK is a superset [elm/core](https://package.elm-lang.org/packages/elm/core/latest) with a few 
  exceptions documented below) 
- A type-safe API for the [Morphir IR](#morphir-ir) that allows you to create or inspect it.

## Installation

```
elm install finos/morphir-elm
```

## Morphir SDK

The goal of the `Morphir.SDK` module is to provide you the basic building blocks to build your domain model and 
business logic. It also serves as a specification for backend developers that describes the minimum set of functionality 
each backend implementation should support.

It is generally based on [elm/core/1.0.5](https://package.elm-lang.org/packages/elm/core/1.0.5/) and provides most of 
the functionality provided there except for some modules that fall outside the scope of business knowledge modeling:
`Debug`, `Platform`, `Process` and `Task`.

Apart from the modules mentioned above you can use everything that's available in `elm/core/1.0.5` without importing 
the `Morphir SDK`. The Elm frontend will simply map those to the corresponding type/function names in the Morphir SDK.

The `Morphir SDK` also provides some features beyond `elm/core/1.0.5`. To use those features you have to import the 
specific `Morphir SDK` module. 

## Morphir IR

The `Morphir.IR` module defines a type-safe API to work with Morphir's intermediate representation. The module 
structure follows the structure of the IR. Here's a list of concepts in a top-down approach:

- [Distribution](https://package.elm-lang.org/packages/finos/morphir-elm/latest/Morphir-IR-Distribution) is the output
  of `morphir-elm make`. It represents a whole package with all of its dependencies.
- [Package](https://package.elm-lang.org/packages/finos/morphir-elm/latest/Morphir-IR-Package) represents a set of 
  modules that are versioned together.
- [Module](https://package.elm-lang.org/packages/finos/morphir-elm/latest/Morphir-IR-Module) is a container
  to group types and values.
- [Types](https://package.elm-lang.org/packages/finos/morphir-elm/latest/Morphir-IR-Type) allow you to describe
  your domain model.
- [Values](https://package.elm-lang.org/packages/finos/morphir-elm/latest/Morphir-IR-Value) allows you to 
  describe your business logic.
- [Names](https://package.elm-lang.org/packages/finos/morphir-elm/latest/Morphir-IR-Name) provide a naming 
  convention agnostic representation for all nodes that can be named: types, values, modules and packages. Names can be 
  composed into hierarchies:
  - [path](https://package.elm-lang.org/packages/finos/morphir-elm/latest/Morphir-IR-Path) is a list of names     
  - [qualifield name](https://package.elm-lang.org/packages/finos/morphir-elm/latest/Morphir-IR-QName) is a module path with a local name
  - [fully-qualifield name](https://package.elm-lang.org/packages/finos/morphir-elm/latest/Morphir-IR-FQName) is a package path with a qualified name
- [AccessControlled](https://package.elm-lang.org/packages/finos/morphir-elm/latest/Morphir-IR-AccessControlled) 
  is a utility to define visibility constraints for modules, types and values  

## Contributing

[Contribution Guide](CONTRIBUTING.md)

1. Fork it (<https://github.com/finos/morphir-elm/fork>)
2. Create your feature branch (`git checkout -b feature/fooBar`)
3. Read our [contribution guidelines](CONTRIBUTING.md) and [Community Code of Conduct](https://www.finos.org/code-of-conduct)
4. Commit your changes (`git commit -am 'Add some fooBar'`)
5. Push to the branch (`git push origin feature/fooBar`)
6. Create a new Pull Request

_NOTE:_ Commits and pull requests to FINOS repositories will only be accepted from those contributors with an active, executed Individual Contributor License Agreement (ICLA) with FINOS OR who are covered under an existing and active Corporate Contribution License Agreement (CCLA) executed with FINOS. Commits from individuals not covered under an ICLA or CCLA will be flagged and blocked by the FINOS Clabot tool. Please note that some CCLAs require individuals/employees to be explicitly named on the CCLA.

*Need an ICLA? Unsure if you are covered under an existing CCLA? Email [help@finos.org](mailto:help@finos.org)*

### Publishing new releases

[Steps for publishing a new release](publishing.md)

## License

Copyright 2014 Morgan Stanley

Distributed under the [Apache License, Version 2.0](http://www.apache.org/licenses/LICENSE-2.0).

SPDX-License-Identifier: [Apache-2.0](https://spdx.org/licenses/Apache-2.0)

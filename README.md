# morphir-elm


morphir-elm is a set of tools to work with Morphir in Elm. It's dual published as an NPM and an Elm package:

- [NPM package](#npm-package)
- [Elm package](#elm-package)

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
morphir-elm [command]
```

Each command has different options which are detailed below:

### Translate Elm sources to Morphir IR

This command reads Elm sources, translates to Morphir IR and outputs the IR into JSON. 

```
morphir-elm make [options]
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

#### Options

- `--project-dir <path>`, `-p`
  - Root directory of the project where morphir.json is located. 
  - Defaults to current directory.
- `--output <path>`, `-o`
  - Target location where the Morphir IR will be sent
  - Defaults to STDOUT.

# Elm package

[![Latest version of the Elm package](https://reiner-dolp.github.io/elm-badges/Morgan-Stanley/morphir-elm/version.svg)](https://package.elm-lang.org/packages/Morgan-Stanley/morphir-elm/latest)

The [Morgan-Stanley/morphir-elm](https://package.elm-lang.org/packages/Morgan-Stanley/morphir-elm/latest) package 
provides various tools to work with Morphir. It contains the following main components:

- The [Morphir SDK](#morphir-sdk) which provides the base set of types and functions that Morphir tools support 
  out-of-the-box. (the SDK is a superset [elm/core](https://package.elm-lang.org/packages/elm/core/latest) with a few 
  exceptions documented below) 
- A type-safe API for the [Morphir IR](#morphir-ir) that allows you to create or inspect it.

## Installation

```
elm install Morgan-Stanley/morphir-elm
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
specific `Morphir SDK` module. Modules that extends `elm/core` will implement the same functions so in general you can 
use an alias if you want to switch from the `elm/core` module to the `Morphir SDK` version. For example if you want to
use extended `List` functions you can do the below an all existing code should continue to work without changes:

```elm
import Morphir.SDK.List as List
```

## Morphir IR

The `Morphir.IR` module defines a type-safe API to work with Morphir's intermediate representation. The module 
structure follows the structure of the IR. Here's a list of concepts in a top-down approach:

- [Package](https://package.elm-lang.org/packages/Morgan-Stanley/morphir-elm/latest/Morphir-IR-Package) represents an
  entire library or application that is versioned as a whole. A package is made up of several modules.
- [Module](https://package.elm-lang.org/packages/Morgan-Stanley/morphir-elm/latest/Morphir-IR-Module) is a container
  to group types and values.
- [Types](https://package.elm-lang.org/packages/Morgan-Stanley/morphir-elm/latest/Morphir-IR-Type) allow you to describe
  your domain model.
- [Values](https://package.elm-lang.org/packages/Morgan-Stanley/morphir-elm/latest/Morphir-IR-Value) allows you to 
  describe your business logic.
- [Names](https://package.elm-lang.org/packages/Morgan-Stanley/morphir-elm/latest/Morphir-IR-Name) provide a naming 
  convention agnostic representation for all nodes that can be named: types, values, modules and packages. Names can be 
  composed into hierarchies:
  - [path](https://package.elm-lang.org/packages/Morgan-Stanley/morphir-elm/latest/Morphir-IR-Path) is a list of names     
  - [qualifield name](https://package.elm-lang.org/packages/Morgan-Stanley/morphir-elm/latest/Morphir-IR-QName) is a module path with a local name
  - [fully-qualifield name](https://package.elm-lang.org/packages/Morgan-Stanley/morphir-elm/latest/Morphir-IR-FQName) is a package path with a qualified name
- [AccessControlled](https://package.elm-lang.org/packages/Morgan-Stanley/morphir-elm/latest/Morphir-IR-AccessControlled) 
  is a utility to define visibility constraints for modules, types and values  

---
id: installation
title: Installation
---
# Morphir Tools Installation and Setup
Morphir provides command line tools for executing morphir tasks. 
These tools are delivered by the ```npm``` package management system. Therefore, installation
requires that ```Node.js``` and ```npm```, whose installation instructions can be found at the [npm site](https://docs.npmjs.com/downloading-and-installing-node-js-and-npm).

## Installation
To install morphir, run:

```npm install -g morphir-elm```

## Setup
The Morphir tools required a configuration file called `morphir.json` located in the project
root directory with the following structure:

```
{
    "name": "My.Package",
    "sourceDirectory": "src"
}
```

An optional section can be added to specify a subset of modules to be used by Morphir:

```
{
    "name": "My.Package",
    "sourceDirectory": "src",
    "exposedModules": [
        "Module",
        "OtherModule"
    ]
}
```


---
id: json-schema-config
---

# Json Schema Config Algorithm
This a basic program execution flow algorithm that runs (for json-schema backend configuration) when a code
generation command is issued:


## CLI Config. Options
* **input** - path to the Morphir IR (morphir-ir.json)
* **output** - directory part for the generated code (./dist)
* **target** - target language to generate (JsonSchema)
* **target-version** - Language version (2020-12)
* **copy-deps** - copy the dependencies used by the generated code (false)
* **limit-to-modules** - Limit the set of modules to be included ('')
* **filename** - filename of the generated Json Schema ('')
* **user-config** - path to the user config file
* **group-by** - Group generated code by package, module or type (package)


## Code Generation Algorithm
1. Check if a configuration filepath is specified and if yes:
   1. read the content of the configuration file
   2. load the config parameters into a variable
   3. assign the program options based on the config
2. If no config filepath is specified:
   1. Set the opts.config to null
   2. Set the values of the JsonBackend-related config
3. Set the values of the non-JsonBackend-related config


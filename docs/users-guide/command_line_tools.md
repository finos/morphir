# Morphir Command Line Tools

## Compile (Elm)
Morphir revolves around the Intermediate Representation (IR), which is the data format for storing logic.
Morphir users compile their business logic into the IR using morphir's compiler tools.  For Elm-authored logic, 
is done through the following:

```shell
morphir-elm make
```

Options include:
```shell
Usage: morphir-elm make [options]

Translate Elm sources to Morphir IR

Options:
-p, --project-dir <path>  Root directory of the project where morphir.json is located. (default: ".")
-o, --output <path>       Target file location where the Morphir IR will be saved. (default: "morphir-ir.json")
-t, --types-only          Only include type information in the IR, no values. (default: false)
-f, --fallback-cli        Full rebuild. (default: false)
-h, --help                display help for command
```

## Visualize
Morphir contains tools to interact with, learn, and test Morphir applications.  This can be invoked via:

```shell
morphir-elm develop
```

Options include:
```shell
Usage: morphir-elm develop [options]

Start up a web server and expose developer tools through a web UI

Options:
  -p, --port <port>         Port to bind the web server to. (default: "3000")
  -o, --host <host>         Host to bind the web server to. (default: "0.0.0.0")
  -i, --project-dir <path>  Root directory of the project where morphir.json is located. (default: ".")
  -h, --help                display help for command
```

Note that the default http://0.0.0.0:3000 sometimes needs to be replaced with http://localhost:3000
depending on the host environment.


## Generate
Morphir provides tools to generate useful things from a Morphir IR.

```shell
morphir-elm gen
```

Options include:
```shell
Usage: morphir-elm gen [options]

Generate code from Morphir IR

Options:
  -i, --input <path>                                               Source location where the Morphir IR will be loaded from. (default: "morphir-ir.json")
  -o, --output <path>                                              Target location where the generated code will be saved. (default: "./dist")
  -t, --target <type>                                              Language to Generate (Scala | SpringBoot | cypher | triples | TypeScript). (default: "Scala")
  -m, --modules-to-include <comma.separated,list.of,module.names>  Limit the set of modules that will be included.
  -h, --help                                                       display help for command
```

### Generate Scala
```shell
morphir-elm gen -t Scala
```

Options include:
```shell
  -e, --target-version <version>                                   Scala language version to Generate. (default: "2.11")
  -c, --copy-deps                                                  Copy the dependencies used by the generated code to the output path. (default: false)
```

### Generate Json Schema
```shell
morphir-elm gen -t JsonSchema
```

Options include:
```shell
  -s, --include-codecs                                             Generate JSON codecs (default: false)
  -f, --filename <filename>                                        Filename of the generated JSON Schema. (default: "")
```

### Generate TypeScript
```shell
morphir-elm gen -t TypeScript
```

### Generate Turtle for semantic web technologies
```shell
morphir-elm gen -t semantic
```

### Generate Cypher for graph databases
```shell
morphir-elm gen -t cypher
```

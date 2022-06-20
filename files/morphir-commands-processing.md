# Morphir-elm Commands Processing


The purpose of the document is to explain what happens when morphir-elm commands are run.
This documents also describes each morphir-elm command, options and output/result of the command.

> **_Note:_** This document is best suited for contributors or anyone interested in understanding how morphir-elm is glued together. You don't need all this information to use Morhpir-elm.

---

All morphir-elm commands are processed in NodeJS. This is because Elm is not built to
work outside a browser and has no way to interact with the terminal.
Morphir-elm uses the elm [javascript-interop](https://guide.elm-lang.org/interop) (i.e. ports) feature to foster communication between the
NodeJS environment and the Elm platform. Code validation and the generation of the IR happens
within Elm.
Here's a list of the commands along with the supported options for each command and what they mean.
<br /> <br /> The following commands are described in this document: <br />
[1. morphir-elm make](#morphir-elm-make) <br />
[2. morphir-elm gen](#morphir-elm-gen) <br />
[3. morphir-elm develop](#morphir-elm-develop) <br />
[4. morphir-elm test](#morphir-elm-test) <br />

# `morphir-elm make`

###Command Description

This command reads elm sources, translates to Morphir IR and outputs the IR into JSON.

|        Option         |   Requires   | Description                                                                               |
|:---------------------:|:------------:|:------------------------------------------------------------------------------------------|
|   `-o`, `--output`    | &lt;path&gt; | Target file location where the Morphir IR will be saved.<br/>(default: "morphir-ir.json") |
| `-p`, `--project-dir` | &lt;path&gt; | Root directory of the project where morphir.json is located.<br/>(default: ".")           |
|    `-h`, `--help`     |      -       | Output usage information.                                                                 |

### Command Execution Process
Here's a description of the processes involved with running the `morphir-elm make` command

The entry point for this command ie specified in [morphir-elm-make.js](https://github.com/finos/morphir-elm/blob/main/cli/morphir-elm-make.js).

Control is handed over to the make function defined in [cli.js](https://github.com/finos/morphir-elm/blob/main/cli/cli.js)
passing in the project directory _(directory where the morphir.json lives)_ and cli arguments/options.

The cli.make function reads the morphir.json contents, reads the Elm source files (files ending with `.elm`),
and passes the source files, morphir.json and cli options to Elm using ports. <br />
> It is worth mentioning that only messages/data is sent between NodeJS and Elm
> and Elm notifies NodeJS when something goes wrong, or when the process is complete
> via commands and subscriptions.

The following ports are used: <br />
1. jsonDecodeError - this is used to receive possible jsonDecode error from Elm <br />
2. packageDefinitionFromSource - this is used to receive send the source files, morphir.json and cli options to Elm [CLI.elm](https://github.com/KindsonTheGenius/morphir-elm/blob/main/cli/src/Morphir/Elm/CLI.elm)  <br />
3. packageDefinitionFromSourceResult - this is used to receive the package definition results from elm.


The entry point responsible for the exposing ports to NodeJS can be found [here](https://github.com/finos/morphir-elm/blob/main/cli/src/Morphir/Elm/CLI.elm).

The update function within elm is immediately triggered when a message comes in through a port.<br />
Visit the [docs on the elm architecture](https://github.com/finos/morphir-elm/blob/main/cli/src/Morphir/Elm/CLI.elm),
and checkout [Commands and Subscriptions](https://guide.elm-lang.org/effects/) to get a better understanding on why the update function is called.

The update function identifies which port the message came through and carries out the next action based on that decision.

The Morphir IR is generated after validation and parsing, and a command is sent out to NodeJS to end the
process with either a success _(which creates the morphir-ir.json and write to it)_ or with a failure which
outputs a failure and message showing where the error might have occurred.

# `morphir-elm gen`

### Command Description

This command reads the Morphir IR and generates the target sources in the specified language.


|            Option            |                   Requires                   | Description                                                                                              |
|:----------------------------:|:--------------------------------------------:|:---------------------------------------------------------------------------------------------------------|
|       `-i`, `--input`        |                 &lt;path&gt;                 | Source location where the Morphir IR will be loaded from.<br/>(default: "morphir-ir.json")               |
|       `-o`, `--output`       |                 &lt;path&gt;                 | Target location where the generate code will be saved<br/>(default: "./dist")                            |
|       `-t`, `--target`       |                 &lt;type&gt;                 | Language to Generate (Scala <code>h</code> SpringBoot  cypher  tri  TypeScript) <br />(default: "Scala") |                                                                  |
|   `-e`, `--target-version`   |               &lt;version&gt;                | Language version to generate.<br/>(default: "2.11")                                                      |
|     `-c`, `--copy-deps`      |            &lt;True or False&gt;             | Copy the dependencies used by the generated code to the output path (True False) <br/>(default: "False") |
| `-m`, `--modules-to-include` | &lt;comma separated list of module names&gt; | Limit the set of modules that will be included.                                                          |

### Command Execution Process
Here's a description of the processes involved with running the `morphir-elm gen` command <br />
The execution process begins with the reading of the Morphir IR from the specified input path. Next, the morphir ir is
stringified and passed into JSON. The resulting object is given to the generate function.
This `generate` function which does three things <br />
1. Subscribes to the jsonDecodeError port <br />
2. Subscribes to the generateResults port <br />
3. Sends the IR together with options to the Elm program (CLI.elm) via the generate port. <br />



# `morphir-elm test`

###Command Description

This command is used to test the test cases present in the morphir-ir.json.

|        Option        |   Requires   | Description                                                                     |
|:--------------------:|:------------:|:--------------------------------------------------------------------------------|
| `-p`, `--projectDir` | &lt;path&gt; | Root directory of the project where morphir.json is located.<br/>(default: ".") |
|

### Command Execution Process
Here's a description of the processes involved with running the `morphir-elm make` command <br />
This command invokes the test() function defined in [cli.js](https://github.com/finos/morphir-elm/blob/main/cli/cli.js).
It takes the project directory (projectDir) as a argument and read content of the morphir-ir.json as well as the morphir-tests.json.
The testResult() function is called with both arguments. <br />
The testResult() function interfaces with the
[CLI.elm](https://github.com/finos/morphir-elm/blob/main/cli/src/Morphir/Elm/CLI.elm) which defines the following ports: <br />
1. jsonDecodeError -  sends jsonDecode error from the Elm ([CLI.elm](https://github.com/finos/morphir-elm/blob/main/cli/src/Morphir/Elm/CLI.elm)) to JavaScript ([cli.js](https://github.com/finos/morphir-elm/blob/main/cli/cli.js)) <br />
2. runTestCasesResultError - sends errors resulting from running the test cases from the Elm ([CLI.elm](https://github.com/finos/morphir-elm/blob/main/cli/src/Morphir/Elm/CLI.elm)) to JavaScript [cli.js](https://github.com/finos/morphir-elm/blob/main/cli/cli.js)) <br />
3. runTestCasesResult -  sends the results of the test cases from the Elm ([CLI.elm](https://github.com/finos/morphir-elm/blob/main/cli/src/Morphir/Elm/CLI.elm)) to JavaScript [cli.js](https://github.com/finos/morphir-elm/blob/main/cli/cli.js)) <br />
4. runTestCases -  receives the test cases to be run sent from Javascript ([cli.js](https://github.com/finos/morphir-elm/blob/main/cli/cli.js)) to Elm ([CLI.elm](https://github.com/finos/morphir-elm/blob/main/cli/src/Morphir/Elm/CLI.elm)) <br />


# `morphir-elm develop`

### Command Description

This command starts a web server and exposes the developer tools via a web UI. The entrypoint for the `morphir-elm develop`
command is specified in the [morphir-elm-develop.js]([CLI.elm](https://github.com/finos/morphir-elm/blob/main/cli/src/Morphir/Elm/CLI.elm)) file.


|     Option     |   Requires   | Description                                                                          |
|:--------------:|:------------:|:-------------------------------------------------------------------------------------|
| `-p`, `--port` | &lt;port&gt; | Port to bind the server to.<br/>(default: "3000")                                    |
| `-o`, `--host` | &lt;host&gt; | Host to bind the server to<br/>(default: "0.0.0.0")                                  |
| `-i`, `--path` | &lt;path&gt; | Root directory of the project where the morphir.json is located <br />(default: ".") |                                                                  |

### Command Execution Process
Here's a description of the processes involved with running the `morphir-elm develop` command <br />
The web pages are located inside the sever/web folder of the project directory.
The following endpoints are exposed by the after by the `morphir-elm develop` command
'/' <br />
'/server/morphir.json - serves the content of the morphir.json file' <br />
'/server/morphir-ir.json - serves the content fo the morphir-ir.json file' <br />
'/server/morphir-tests.json - (GET) serves te content of the morphir-tests.json file' <br />
'/server/morphir-tests.json - (POST) accepts a request as morphir-test.json as request body, creates the morphir-tests.json
and returns the content as response' <br />


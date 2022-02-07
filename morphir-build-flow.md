# Morphir-elm Command Processes


The purpose of the document is to explain what happens when morphir-elm commands are run.
This documents also describes each morphir-elm command, options and output/result of the command. 

> **_Note:_** This document is best suited for contributors or anyone interested in understanding how morphir-elm is glued together. You don't need all this information to use Morhpir-elm.

---

All morphir-elm commands are processed in NodeJS. This is because Elm is not built to 
work outside a browser and has no way to interact with the terminal. 
Morphir-elm uses the elm [javascript-interop](https://guide.elm-lang.org/interop) (i.e. ports) feature to foster communication between the
NodeJS environment and the Elm platform. Code validation and the generation of the IR happens
withing Elm.

## Command Description
Here's a list of the commands along with the supported options for each command and what they mean.

### `morphir-elm make`

This command reads elm sources, translates to Morphir IR and outputs the IR into JSON.

|        Option         |   Requires   | Description                                                                               |
|:---------------------:|:------------:|:------------------------------------------------------------------------------------------|
|   `-o`, `--output`    | &lt;path&gt; | Target file location where the Morphir IR will be saved.<br/>(default: "morphir-ir.json") |
| `-p`, `--project-dir` | &lt;path&gt; | Root directory of the project where morphir.json is located.<br/>(default: ".")           |
|    `-h`, `--help`     |      -       | Output usage information.                                                                 |

## Command Process
Here's a description of the processes involved with running each of these command

### `morphir-elm make`

The entry point for this command can be found [here](https://github.com/finos/morphir-elm/blob/main/cli/morphir-elm-make.js).

Control is handed over to the make function defined in [cli.js](https://github.com/finos/morphir-elm/blob/main/cli/cli.js) 
passing in the project directory _(directory where the morphir.json lives)_ and cli arguments/options. 

The cli.make function reads the morphir.json contents, reads the Elm source files (files ending with `.elm`),
and passes the source files, morphir.json and cli options to Elm using ports. <br />
> It is worth mentioning that only messages/data is sent between NodeJS and Elm
> and Elm notifies NodeJS when something goes wrong, or when the process is complete 
> via commands and subscriptions.

The entry point responsible for the exposing ports to NodeJS can be found [here](https://github.com/finos/morphir-elm/blob/main/cli/src/Morphir/Elm/CLI.elm).

The update function within elm is immediately triggered when a message comes in through a port.<br />
Visit the [docs on the elm architecture](https://github.com/finos/morphir-elm/blob/main/cli/src/Morphir/Elm/CLI.elm),
and checkout [Commands and Subscriptions](https://guide.elm-lang.org/effects/) to get a better understanding on why the update function is called.

The update function identifies which port the message came through and carries out the next action based on that decision.

The Morphir IR is generated after validation and parsing, and a command is sent out to NodeJS to end the 
process with either a success _(which creates the morphir-ir.json and write to it)_ or with a failure which
outputs a failure and message showing where the error might have occurred.
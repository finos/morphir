---
id: contribution-guide
title: Contribution Guide
---

# Contribution Guide

The purpose of this document is to make it easier for new contributors to get up-to-speed on the project.

## Project Setup

### JavaScript Tooling

The project uses Node.js and NPM as the runtime and package manager. You can download them from 
[this link](https://nodejs.org/en/download/).

We use [Gulp](https://gulpjs.com/) as our build tool. You can use NPM to install it:

```
npm install -g gulp
```

### Elm Tooling

The easiest way to install the Elm tooling is using NPM. Here's a list of Elm tools we use:

- `npm install -g elm`
- `npm install -g elm-test`
- `npm install -g elm-format`
- `npm install -g elm-live` 

#### Installing an elm-format git pre-commit hook

If you wish to run elm-format on files that you are commiting to git, copy the following script to morphir-elm/.git/pre-commit and make it executable:

```
#!/usr/bin/env bash

STAGED_ELM_FILES=$(git diff --cached --name-only --diff-filter=ACMR | grep ".elm$")

# If any elm-format command fails, exit immediately with that command's exit status
set -eo pipefail

if [[ -n "$STAGED_ELM_FILES" ]] ; then
    GIT_DIR=$(pwd)
    # Run elm-format against staged elm files for this commit
    for ELM_FILE in $STAGED_ELM_FILES ; do
        ELM_PATH="$GIT_DIR/$ELM_FILE"
        elm-format --yes "$ELM_PATH"
    done
fi
```

By default elm-format will be run for each file ending in '.elm', when they are commited. 
If you don't wish to run elm-format, use the '--no-verify' option with your commit command.

### IDE

Most contributors are using [IntelliJ](https://www.jetbrains.com/idea/download) with the 
[Elm plugin](https://plugins.jetbrains.com/plugin/10268-elm). [VS Code](https://code.visualstudio.com/download) with the 
[Elm plugin](https://marketplace.visualstudio.com/items?itemName=Elmtooling.elm-ls-vscode) is another popular choice.

## Learning Material

In order to contribute to this project you need to be familiar with Elm and understand some language processing / compiler concepts that are core to Morphir. 
We collected a series of learning materials for you to make it easier to fill any knowledge gaps. Feel free to skip any of these if you feel like you are an expert. 
If you have any doubts though it's better to glance through them. We included the length of each video so that you understand the amount of effort involved.

- Programming in Elm
  - Language Overview
    - [Official language guide](https://guide.elm-lang.org/)
    - [Quick overview of Elm with comparisons to JavaScript](https://www.youtube.com/watch?v=um0jxfgboNo) (10 mins)
    - [Longer overview with a focus on how Elm makes your app more reliable](https://www.youtube.com/watch?v=kEitFAY7Gc8) (45 mins)
  - Working with Types
    - [Chapter on Types from the official language guide](https://guide.elm-lang.org/types/)
    - [Elm type system basics](https://www.youtube.com/watch?v=F_bx2J8En9w) (2 mins)
    - [Algebraic Data Types](https://www.youtube.com/watch?v=JYWJzaiCtEw) (10 mins)
    - [Deeper dive into how types can help you](https://www.youtube.com/watch?v=memIRXFSNkU) (30 mins)
- Language processing
  - Abstract Syntax Trees
    - [Intro](https://www.youtube.com/watch?v=jpfaXK4xCYE) (3 mins)
    - [Deeper dive](https://www.youtube.com/watch?v=VKM1eLoN-gI) (12 mins)



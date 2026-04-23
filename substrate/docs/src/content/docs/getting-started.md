---
title: Install & quickstart
description: Install the substrate CLI and run your first spec.
breadcrumb: ["Start here", "Install & quickstart"]
---

## Install

Substrate ships as a Node.js CLI. You will need **Node 20+** and **npm 10+**.

```bash
npm install -g substrate
```

Verify the install:

```bash
substrate --version
```

## Your first spec

Substrate specs are plain Markdown. Create `hello.md`:

````markdown
# Hello

A substrate spec that greets the world.

```substrate
function greet(name: String) -> String =
  "Hello, " + name + "!"
```

## Example

`greet("world")` should return `"Hello, world!"`.
````

Run it:

```bash
substrate run hello.md
```

## Validate a project

To check that every spec in a directory is well-formed:

```bash
substrate validate ./specs
```

## Install / update packages

Substrate specs can depend on other specs. Use the package commands to
manage those dependencies:

```bash
substrate install   # install dependencies declared in substrate.toml
substrate update    # refresh locked versions
substrate publish   # publish the current package to the registry
```

## Next steps

- Read the [language specification](/docs/specs/language/) for syntax and semantics.
- Browse the [examples](https://github.com/AttilaMihaly/morphir-substrate/tree/main/examples) for fully-worked specs.
- See the [CLI reference](/docs/specs/tools/cli/) for every command and flag.

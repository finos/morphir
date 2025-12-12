---
id: adr-for-morphir-cli
sidebar_position: 1
---

# ADR for Morphir CLI incremental build approach

## Context and Problem Statement

### Context

Morphir CLI tool offers a way to convert business models into the **Morphir IR** by parsing source files when a `make` command is run. The tooling performs poorly on very large models with especially syntactically complex logics. The initial approach to building the **Morphir IR** was to read all the source files and process them to produce the **IR**. This approach is obviously inefficient because we do not need to read and parse all source files every other time the `make` command is run. We decided to **Build Incrementally**.

### Problem

Our approach to building incrementally captures and processes changes on a modular level. However, different types of changes within a module would require the modules to be processed in different orders to complete successfully.

**Example**
Assuming module `Foo` has a function called `foo` that depends on a function called `bar` in module `Bar`, and `bar` has no dependencies.

``` mermaid
        flowchart LR
            foo ---> bar
            subgraph Foo
                foo
            end
            subgraph Bar
                bar
            end 
```

_diagram showing modules Foo and Bar and the dependency between them._

Example of operations that require special orderings:

* Updating `Foo.foo` to no longer depend on `Bar.bar` and deleting `Bar.bar`. This requires `Foo.foo` to be processed first to remove the dependency between `Foo.foo` and `Bar.bar` before deleting `Bar.bar`.

* Updating type `Foo.foo` to depend on a new type `Bar.fooBar`. This requires processing `Bar.fooBar` to include the new type before processing `Foo.foo` to add that dependency.

What is the best approach to building incrementally?

## Decision Drivers <!-- optional -->

* Tooling Performance
* Maintainability
* Meaningful error reporting

## Considered Options

* Process changes in any order and validate the final result (Repo)
* Capture, order, and apply changes on a granular level
* Order modules dependency and then proceed with option 2

## Decision Outcome

Chosen option: "Option 3", Only option three, by design, takes all decision drivers into account.

### Positive Consequences

* Allows for name resolution and also allows type inferencing to be done at an early stage.
* Excellent error reporting is possible because we process changes at a granular level.
* It improves tooling performance.

### Negative Consequences

* It introduces a level of complexity.

## Pros and Cons of the Options

### Process changes in any order and validate the final result (Repo)

Processing in this manner simply means that after changed modules (inserted, deleted or updated modules) have been collected, we proceed to process the changes that occurred without re-ordering modules, types or values.
After all processing has been done, then we attempt to validate the Repo (the output of the process) and error out if the repo is invalid.

* Good, because It's fast.
* Good, because this approach isn't complex.
* Bad, because it doesn't take name resolution into account.
* Bad, because type inferencing would be done at the very end which takes away the benefit of {agument 1}.
* Bad, as it would be difficult to collect meaningful errors after validating the repo.

### Capture, order, and apply changes on a granular level

Capturing changes on a granular level simply means that instead of detecting that `module Foo` has been updated, we could further detect that `foo` is what was updated within `Foo`, and further capture changes like **access levels changes**, **deletes**, **type Constructor added**, etc. making it as granular as possible.
After capturing the changes, we could calculate the correct order to process each granular change before processing the changes.

* Good, because It's allows for excellent error reporting
* Good, because it's fast
* Bad, because it modifies the API of the Repo and adds complexity
* Bad, because proper name resolution would not be possible.
* Bad, because type inferencing would be done at the very end which takes away the benefit of {agument 2}.

### Order modules dependency and then proceed with option 2

With this approach, we first order the collected modules by dependency and then proceed to collect granular changes.

* Good, because it's fast.
* Good, because it allows for excellent error reporting.
* Good, because names can be resolved.
* Good, because types can be inferred.
* Bad, because it adds complexity to the API

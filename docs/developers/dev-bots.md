---
id: dev-bots
title: Explaining Dev Bots
sidebar_position: 5
---

# Explaining Dev Bots

The premise of Dev Bots is that we can and should automate a significant portion of the code that we currently write by hand.

Consider the portion of an application's code that is of no direct business value, includeing things like
persistence and ORM, interprocess communication, platform-specific code, object wiring, and more. We need this code
to make our applications run, but it is of no direct business value. A large portion of this non-business code comes
in the form of recipes to follow or "best practices" templates. The fact that it takes up the majority of our
applications often reduces us to human code robots. We often refer to this code as boilerplate, and it is
highly amenable to automation.

We can also look into automating certain aspects of business code. Much of that code also follows templates and best
practices, and as a result, there is an abundance of tools that process code for quality and conformance
to rules. These tools ensure that the code that developers write fits into a small window of variability. Again,
developers are reduced to human code robots. You have to wonder: _If we have such sophisticated tools that automatically
ensure that all of our code conforms to a limited set of templates after the code is written, why don't we have tools
that automatically write the code to those specifications in the first place?_ The answer is that we can.

This is what Morphir Dev Bots do. They automate the production of all the boilerplate and templated code and
let developers focus on what they do best: provide the bridge between the business and computer world.

[Home](/index) | [Posts](posts) | [Examples](https://github.com/finos/morphir-examples/)

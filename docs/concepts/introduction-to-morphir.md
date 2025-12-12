---
id: introduction-to-morphir
title: Introducing Morphir
---

[![FINOS - Incubating](https://cdn.jsdelivr.net/gh/finos/contrib-toolbox@master/images/badge-incubating.svg)](https://finosfoundation.atlassian.net/wiki/display/FINOS/Incubating)
[![CII Best Practices](https://bestpractices.coreinfrastructure.org/projects/6526/badge)](https://bestpractices.coreinfrastructure.org/projects/6526)
<!-- [<img src="https://img.shields.io/badge/slack-@finos/morphir-green.svg?logo=slack">](https://finos-lf.slack.com/messages/morphir/) -->

# Morphir

Morphir is a library of tools that works to capture business logic as data.

For the first time, business logic can be shared, stored, translated and visualised, all with the reliability of standardisation ensured in the Morphir framework.

## What is it?

A set of tools for integrating technologies. Morphir is composed of a library of tools that facilitate the digitisation of business logic into multiple different languages & platforms. The Morphir framework is unique too in that facilities elements of automation and conversion that were previously unavailable in the field of finance-tech.

## Why is it important?

Makes business logic portable. Business logic digitised provides distinct advantages: capacity for movement across departments and fields & the ability to be converted to new languages and applications.

## How does it work?

Defines a standard format for storing and sharing business logic. A clear set of standards and format is in-place from the input/output, allowing for coherent structure.

## What are the benefits?

### ✔️ Eliminates technical debt risk

> _Refactoring code libraries is often a harmful and time-sensitive issue for businesses, Morphir ensure the standards introduced from input eliminate delays at deployment._

### ✔️ Increases agility

> _Adaptability and usability are key concepts of the Morphir framework, business logic can now move with the code, be easily understood and adopted, in an ever-developing eco-system._

### ✔️ Ensures correctness

> _Certifying that specified functions behave as intended from input to output is assured through the Morphir library / tool chain._

### ✔️ Disseminates information through automation

> _Morphir’s automated processing helps disseminate information which otherwise may not be understood or shared at all, a useful tool when brining elements of business logic to conversation outside of its immediate audience (i.e developers)._


## Documentation
If you want to start using Morphir, start with the [Documentation](docs/).

## The Morphir Projects
Morphir consists of a few projects based on the features they provide.

### Core Morphir Projects
- **[morphir (this project)](https://github.com/finos/morphir/)** - The umbrella project
- **[morphir-elm](https://github.com/finos/morphir-elm)** - Contains most of the core morphir functionality, including:
    - The definition of the IR
    - The Elm compiler for authoring morphir applications in Elm
    - The morphir visualization components and developer tools
    - The Scala, JSON Schema, TypeScript, TypeSpec (Cadl), cypher, semantic, and more backend processors.
- **[morphir-jvm](https://github.com/finos/morphir)** - Supporting SDK and packaging for running morphir on the JVM.
- **[morphir-examples](https://github.com/finos/morphir-examples)** - A whole lot of examples.

### Incubator Morphir Projects
- **[morphir-scala](https://github.com/finos/morphir-scala)** - Tight integration with Scala for authoring, execution, and writing tools.
- **[morphir-bosque](https://github.com/finos/morphir-bosque)** - Integration with the Bosque language.
- **[morphir-dotnet](https://github.com/finos/morphir-dotnet)** - Integration with .NET via F#.


## Other Resources
[List of media](../community/media.md)


### Further reading

| Introduction & Background                                             | Using Morphir                                                                                              | Applicability                                                                      |
|:----------------------------------------------------------------------|:-----------------------------------------------------------------------------------------------------------|:-----------------------------------------------------------------------------------|
| [Resource Centre](https://resources.finos.org/morphir/)               | [What Makes a Good Model](../user-guides/what-makes-a-good-domain-model.md)                                             | [Sharing Business Logic Across Application Boundaries](../shared_logic_modeling.md) |
| [Background](../Morphir%20Overview/background.md)                                         | [Development Automation (Dev Bots)](../developers/dev-bots.md)                                                         | [Regulatory Technology](../use-cases/regtech-modeling.md)                                     |
| [Community](../community/morphir-community.md)                                   | [Modeling an Application](../user-guides/application-modeling.md)                                                       |                                                                                    |
| [What's it all about?](./whats-it-about.md)                           | [Modeling Decision Tables](https://github.com/finos/morphir-examples/tree/master/src/Morphir/Sample/Rules) |                                                                                    |
| [Why we use Functional Programming?](./why-functional-programming.md) | [Modeling for database developers](../user-guides/modeling-for-database-developers.md)                                  |

## Roadmap

List the roadmap steps; alternatively link the Confluence Wiki page where the project roadmap is published.

1. Enhanced Scala support
2. Further enhancements for Application modeling with Dapr and Spring Boot.
3. Support for Microsoft's Bosque language for defining models.
4. Modeling queries and aggregations across databases and event processing.

## Contributing

1. Fork it (<https://github.com/finos/morphir/fork>)
2. Create your feature branch (`git checkout -b feature/fooBar`)
3. Read our [contribution guidelines](../developers/contributing.md) and [Community Code of Conduct](https://www.finos.org/code-of-conduct)
4. Commit your changes (`git commit -am 'Add some fooBar'`)
5. Push to the branch (`git push origin feature/fooBar`)
6. Create a new Pull Request

_NOTE:_ Commits and pull requests to FINOS repositories will only be accepted from those contributors with an active, executed Individual Contributor License Agreement (ICLA) with FINOS OR who are covered under an existing and active Corporate Contribution License Agreement (CCLA) executed with FINOS. Commits from individuals not covered under an ICLA or CCLA will be flagged and blocked by the FINOS Clabot tool. Please note that some CCLAs require individuals/employees to be explicitly named on the CCLA.

_Need an ICLA? Unsure if you are covered under an existing CCLA? Email [help@finos.org](mailto:help@finos.org)_

## Join the Morphir Slack Channel

Join Morphir on the FINOS Slack by signing up [here](https://finos-lf.slack.com/). 
The Morphir channel on Slack is found directly [here](https://finos-lf.slack.com/messages/morphir/)

<!-- [<img src="https://img.shields.io/badge/slack-@finos/morphir-green.svg?logo=slack">](https://finos-lf.slack.com/messages/morphir/) -->

Reach out to help@finos.org for any issues when joining Morphir on the FINOS Slack.

## License

Copyright 2022 FINOS

Distributed under the [Apache License, Version 2.0](http://www.apache.org/licenses/LICENSE-2.0).

SPDX-License-Identifier: [Apache-2.0](https://spdx.org/licenses/Apache-2.0)
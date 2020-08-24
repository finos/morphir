[![FINOS - Incubating](https://cdn.jsdelivr.net/gh/finos/contrib-toolbox@master/images/badge-incubating.svg)](https://finosfoundation.atlassian.net/wiki/display/FINOS/Incubating)
![website build](https://github.com/finos/morphir/workflows/Docusaurus-website-build/badge.svg)

# Morphir

**Morphir** is a multi-language system built on a data format that captures an application's domain model and business logic in a technology agnostic manner. Having all the business knowledge available as data allows you to process it programatically in various ways:

- **Translate it** to move between languages and platforms effortlessly as technology evolves
- **Visualize it** to turn black-box logic into insightful explanations for your business users
- **Share it** across different departments or organizations for consistent interpretation
- **Store it** to retrieve and explain earlier versions of the logic in seconds
- and much more ...

Read more [Morphir documentation](https://morgan-stanley.github.io/morphir/)

## Morphir IR

The heart of Morphir is an intermediate representation that captures the domain model and business logic of your application. 
Our main serialization format is JSON for maximum language interoperability. This repo will contain the specification of the JSON
format in the near future. While we are working on it you can check out the documentation of the corresponding 
[Elm library](https://github.com/Morgan-Stanley/morphir-elm#morphir-ir) to get an idea on the structure.

## Morphir sub-projects:

**Core**
* [morphir](https://github.com/Morgan-Stanley/morphir) - The core IR data structure and common SDK.
* [morphir-examples](https://github.com/Morgan-Stanley/morphir-examples) - Examples of various types of Morphir modeling (mostly in Elm).

**Frontends**
* [morphir-elm](https://github.com/Morgan-Stanley/morphir-elm) - Enabling Elm as a Morphir modeling language.
* [morphir-bosque](https://github.com/Morgan-Stanley/morphir-bosque) - Enabling Bosque as a Morphir modeling language.
* [morphir-dotnet](https://github.com/Morgan-Stanley/morphir-dotnet) - Enabling F# as a Morphir modeling language and for .NET as a backend target.

**Backends**
* [morphir-dapr](https://github.com/Morgan-Stanley/morphir-dapr) - Enabling Microsoft's [Dapr](http://dapr.io) as a target application model platform.
* [morphir-jvm](https://github.com/Morgan-Stanley/morphir-jvm) - Enabling various JVM technologies as targets for Morphir model execution.
* [morphir-dotnet](https://github.com/Morgan-Stanley/morphir-dotnet) - Support for using F# as a Morphir modeling language and for .NET as a backend target.

## Installation

The quickest way to start is to use the Morphir Elm tooling.  You can find instructions [here](../../morphir-elm/).

## Usage example

Morphir tools can be used to optimize a wide range of development tasks.  For example, Morphir can be used to define and automated development of an entire service.  The [Morphir Dapr](../../morphir-dapr) project is example of this.

Another good use of Morphir is to define shared rules than can be used across heterogeneous systems.  This can be useful for initiatives like open-source Reg Tech models that are shared across firms.  [Morphir LCR](../../morphir-examples/src/Morphir/Sample/LCR/) presents a good example of this.

More Morphir examples can be found at [Morphir Examples](../../morphir-examples/).

## Development setup

Morphir is a collection of tools.  Each tool is in its own repo with its own installation instructions.  The main development tools, and the best place to get started, are currently in [Morphir Elm](../../morphir-elm).  

## Roadmap

List the roadmap steps; alternatively link the Confluence Wiki page where the project roadmap is published.

1. Enhanced Scala support
2. Further enhancements for Application modeling with Dapr and Spring Boot.
3. Support for Microsoft's Bosque language for defining models.
4. Modeling queries and aggregations across databases and event processing.

## Contributing

1. Fork it (<https://github.com/finos/morphir/fork>)
2. Create your feature branch (`git checkout -b feature/fooBar`)
3. Read our [contribution guidelines](.github/CONTRIBUTING.md) and [Community Code of Conduct](https://www.finos.org/code-of-conduct)
4. Commit your changes (`git commit -am 'Add some fooBar'`)
5. Push to the branch (`git push origin feature/fooBar`)
6. Create a new Pull Request

_NOTE:_ Commits and pull requests to FINOS repositories will only be accepted from those contributors with an active, executed Individual Contributor License Agreement (ICLA) with FINOS OR who are covered under an existing and active Corporate Contribution License Agreement (CCLA) executed with FINOS. Commits from individuals not covered under an ICLA or CCLA will be flagged and blocked by the FINOS Clabot tool. Please note that some CCLAs require individuals/employees to be explicitly named on the CCLA.

*Need an ICLA? Unsure if you are covered under an existing CCLA? Email [help@finos.org](mailto:help@finos.org)*


## License

Copyright 2020 FINOS

Distributed under the [Apache License, Version 2.0](http://www.apache.org/licenses/LICENSE-2.0).

SPDX-License-Identifier: [Apache-2.0](https://spdx.org/licenses/Apache-2.0)

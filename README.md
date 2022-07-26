# Morphir Developers' Guide
The purpose of the document is to provide a detailed explanation of how various Morphir code artefacts work.
It also documents the standard coding practices adopted for the Morphir project.
Finally, it provides a step by step walk-throughs on how various Morphir components are build.

### Who this Guide Designed For
1. New joiners to the Morphir project to get up to speed the various building blocks of Morphir
2. Existing team members intending to improve their abilities on Language Design concepts

##Content
1. [Getting Started with Morphir](https://github.com/finos/morphir-elm/blob/main/README.md) <br>
2. [Overview of Morphir](#)
3. [The Morphir Architecture](#) <br>
4. [The Morphir SDK](#) <br>
5. [Morphir Commands Processing](Morphir-elm Commands Processing) <br>
    1. [morphir-elm make](#) <br>
    2. [morphir-elm gen](#) <br>
    3. [morphir-elm test](#) <br>
    4. [morphir-elm develop](#) <br>
6. [Interoperability With JavaScript](#) <br>
7. [Testing Framework](#) <br>
8. [The Morphir IR](#) <br>
    1. [Overview of the Morphir IR](#) <br>
    2. [Distribution](#) <br>
    3. [Package](#) <br>
    4. [Module](#) <br>
    5. [Types](#) <br>
    6. [Values](#) <br>
    7. [Names](#) <br>
9. [The Morphir Frontends](#) <br>
    1. [Elm Frontend](#) <br>
    2. [Elm Incremental Frontend](#) <br>
10. [The Morphir Backends](#) <br>
    1. [Scala Backend](https://github.com/finos/morphir-elm/blob/main/docs/developers-guide/files/scala-backend.md)
    2. [Spark Backend](https://github.com/finos/morphir-elm/blob/main/docs/developers-guide/files/spark-backend.md)
    3. [Relational IR Backends](https://github.com/finos/morphir-elm/blob/main/docs/developers-guide/files/relational-backend.md)
    4. [Scala Json Codecs Backend](https://github.com/finos/morphir-elm/blob/main/docs/developers-guide/files/scala-backend.md)
11. [Working with CODECS](#) <br>
    1. [Introduction to Encoding/Decoding](#) <br>
    2. [JSON Decoder Building Blocks](#) <br>
    3. [Combining Decoders](#) <br>
    4. [JSON Decode Pipeline](#) <br>
    5. [Writing Encoders and Decoders in Elm](#) <br>
    6. [Standard Codecs in Morphir](#) <br>
12. [NPM and Elm Packages](#) <br>
13. [Introduction to Combinator Parsing in Scala](#) <br>
    1. [Overview of Combinator Parsing](#) <br>
    2. [Parser or Basic Arithmetic Expression](#) <br>
    3. [Implementing Parsers in Scala](#) <br>
    4. [Regular Expressions Parser](#) <br>
    5. [JSON Parser](#) <br>
    6. [Low-Level Pull Parser API](#) <br>


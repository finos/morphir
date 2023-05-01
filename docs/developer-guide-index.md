# Morphir Developers' Guide
The purpose of the document is to provide a detailed explanation of how various Morphir code artefacts work.
It also documents the standard coding practices adopted for the Morphir project.
Finally, it provides a step by step walk-throughs on how various Morphir components are build.

### Who this Guide Designed For
1. New joiners to the Morphir project to get up to speed the various building blocks of Morphir
2. Existing team members intending to improve their abilities on Language Design concepts

##Content
1. [Getting Started with Morphir](README.md) 
2. [Overview of Morphir](#)
3. [The Morphir Architecture](#) 
4. [The Morphir SDK](#) 
5. [Morphir Commands Processing](Morphir-elm Commands Processing) 
    1. [morphir-elm make](#) 
    2. [morphir-elm gen](#) 
    3. [morphir-elm test](#) 
    4. [morphir-elm develop](#) 
6. [Interoperability With JavaScript](#) 
7. [Testing Framework](#) 
    1. [CSV testing guide ](spark-testing-framework.md)
8. [The Morphir IR](#) 
    1. [Overview of the Morphir IR](#) 
    2. [Distribution](#) 
    3. [Package](#) 
    4. [Module](#) 
    5. [Types](#) 
    6. [Values](#) 
    7. [Names](#) 
9. [The Morphir Frontends](#) 
    1. [Elm Frontend](#) 
    2. [Elm Incremental Frontend](#) 
10. [The Morphir Backends](#) 
    1. [Scala Backend](scala-backend.md)
    2. [Spark Backend](spark-backend.md)
    3. [Relational IR Backends](relational-backend.md)
    4. [Scala Json Codecs Backend](scala-backend.md)
    5. [Json Schema Backend](json-schema-mappings.md)
11. [Working with CODECS](#) 
    1. [Introduction to Encoding/Decoding](#) 
    2. [JSON Decoder Building Blocks](#) 
    3. [Combining Decoders](#) 
    4. [JSON Decode Pipeline](#) 
    5. [Writing Encoders and Decoders in Elm](#) 
    6. [Standard Codecs in Morphir](#) 
12. [NPM and Elm Packages](#) 
13. [Introduction to Combinator Parsing in Scala](#) 
    1. [Overview of Combinator Parsing](#) 
    2. [Parser or Basic Arithmetic Expression](#) 
    3. [Implementing Parsers in Scala](#) 
    4. [Regular Expressions Parser](#) 
    5. [JSON Parser](#) 
    6. [Low-Level Pull Parser API](#) 


---
id: scala-api
title: Scala API Guide
---


# Scala API User Guide 
## Overview 
This document explains what the Scala API is, how to import it and example usages.  
The API exposes the internals of an IR to a developer to be able to build tools in scala. The API consist of mainly : 
1. [Utility Functions](#) - for performing actions and receiving data on the IR 
2. [Codecs](#) - for JSON serialization. 


## How to Import the API
The API is published as a versioned maven package with naming convention such as `morphir-ir_2.13`.  
Importing this package would vary based on the project's build tool. For more information on how to import a maven package, 
checkout the project's build tool documentation. 

## How to Use the API ?
The API is mainly dependent on these two packages: 
1. [morphir sdk](https://package.elm-lang.org/packages/finos/morphir-elm/latest/Morphir-SDK-Aggregate) - for its basic and advance types  
2. [io.circe](https://circe.github.io/circe/parsing.html) - for JSON Serialization.  

### Below are usage examples

1. **Reading the IR into a Distribution using Decoder**.  
This example reads the content of the `morphir-ir.json`, parses it into JSON then decode it into a Scala distribution type.
```scala
 val iRContent: String = Source.fromFile("path-to-morphir-ir.json").mkString
 val irJson: Json = parser.parse(iRContent)
 Codec.decodeDistributionVersion.decodeJson(irJson.getOrElse(Json.Null)) match {
   case Left(err: DecodingFailure) => ???
   case Right(distribution: Distribution) => ???
 }
```
2. **Traversing the IR using utility functions**.  
This example obtains the package name from the distribution, gets the package specification and list all modules within. 
```scala
val packageName: PackageName = lookupPackageName(distribution)
val packageSpec: Package.Specification[scala.Unit] = lookupPackageSpecification(distribution)
val allModuleList: List[Module.ModuleName] = packageSpec.modules.keys.toList
println("Modules In Package : ")
allModuleList.foreach(println(s"\t ${Path._toString(Name.toTitleCase)(".")(modName)}"))
```
3. **Writing a distribution to a JSON using Encoder**
```scala
val newIRContent =  Codec.encodeDistribution(distribution).as[Json]
```

## Reference
The API is a complete replica of the [Elm's API](https://package.elm-lang.org/packages/finos/morphir-elm/latest/Morphir-IR). 
implemented in Scala. To read more on the docs of each utility function, please reference the 
[Elm Package](https://package.elm-lang.org/packages/finos/morphir-elm/latest/Morphir-IR)
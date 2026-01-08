---
id: json-codecs-doc
sidebar_position: 1
---
# Json Codec Backend
The purpose of this documentation is to give an explanation of how the Json Codec Backend works and how to use it.
The Json Codec backend is a tool that generates encoders and decoders from a Morphir IR using the Circe JSON library. Codecs are generated in Scala

### How to use the JSON Codec Backend

The first step to using the JSON Codec backend is to add the Circe JSON library to your project. This can be done in two ways:
1. Add the Circe JSON dependency through your project build tool eg. Sbt, Mill etc.
2. Add ```morphir-jvm``` as a dependency to your project.

#### Generating Codecs from the IR
The backend is built to generate codecs for only types so when generating an IR , the ```-t``` flag which specifies ```--types-only``` should be used. Also, we want to add the ```-f``` flag to use the old CLI make function.

To generate Codecs from the  IR:
1. Run ```morphir-elm make -f -t``` to generate the IR.
2.  Run ```morphir-elm gen -s``` to generate the codecs
3.  In the situation where you do not have ```morphir-jvm``` as a dependency in your project, you have to add the ```-c``` flag to copy dependencies from the ```morphir-jvm``` project. Complete command for this is ```morphir-elm gen -s -c```


#### Unsupported Features
Codecs are not generated for Function types in the morphir ir.
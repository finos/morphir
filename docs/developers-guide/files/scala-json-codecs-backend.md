# Scala JSON-Codecs Backend Documentation

This documents provides a description of the JSON codecs backend.
The Json Codecs Backend for Scala contains function to generating Codecs from types in the IR.<br>
[Circe](https://circe.github.io/circe/) is used as the base JSON library.

## 1. Elm Type to Scala Type Mapping
This section describes the mapping of Elm types to Scala Codec. It's important to note that all codecs generated from the Elm types
are Scala values defined in the Scala AST. The Codec files generated contains value declarations as lamda functions.
Below is an outline of how each type is mapped

#### Variable
Variable types in Elm are mapped to Scala Variables

#### Reference
Reference types in Elm are mapped to Scala Ref which uses the Elm path and name
to create a Scala Ref value

#### Tuple 
Not completed yet

#### Record
An Elm record type maps to Circe object which consists of a list of fields which are applie
the Circe.json.obj function.


#### ExtensibleRecord
Similar to a record

#### Function
Function are currently not mapped.

#### Unit
Function are currently not mapped.


#### Custom Type Definition



## 2.  Scala Json Codecs Backend Functions
The following functions are defined in the Json-Codecs:

#### generateEncodeReference


#### generateDecodeReference


#### mapTypeDefinitionToEncoder


#### mapTypeDefinitionToDecoder


#### composeEncoders


#### composeDecoders

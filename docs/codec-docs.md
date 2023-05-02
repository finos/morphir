---
id: codec-docs
title: Scala JSON Serialization
---

# JSON serialization support for generated Scala classes

The purpose of this documentation is to give an explanation on how the JSON Codec Backend works and how to use it.
This backend is a feature built on top of the Scala backend, which allows you to read Scala types that the Scala backend generates from JSON and write to JSON.

### How to use the JSON Codec Backend

The first step to using the JSON Codec backend is to add the Circe JSON library and ```morphir sdk``` as dependencies to your project. The ```morphir sdk``` can be added to your project through the following ways:

1. Copy dependencies from ```morphir-jvm``` : This option allows you to copy the dependencies(morphir sdk) used by the generated code to the output path. You can achieve this by adding the ```-c``` or ```--copy-deps``` flag to the ```morphir-gen``` command.

2. Adding from `Maven Repository` : The SDK can be added from the maven repository as a dependency . It can be found at [Morphir SDK Core](https://search.maven.org/search?q=a:morphir-sdk-core_2.12).


#### Generating Codecs from the IR
The ```morphir-ir.json``` is a prerequisite to generating codecs. Make sure you have that and proceed with the following steps

1.  Run ```morphir-elm gen --include-codecs --target Scala``` to generate the codecs
2. In the situation where you do not have ```morphir sdk``` as a dependency in your project, you have to add the ```--copy-deps``` flag to copy dependencies from the ```morphir-jvm``` project. Complete command for this is ```morphir-elm gen --iclude-codecs --copy-deps --target Scala```.

### How to use Generated Codecs
Using an example , lets describe a model structure and look at how the generated codec for this particular model will be structured

The model:

	- reference-model
      - src
        - Morphir
          - Reference
	        - Model
              - BooksAndRecords.elm  
	- morphir.json
	- morphir-ir.json


Running the command  ```morphir-elm gen --include-codecs --copy-deps --output codecs/src``` to generate codecs means your codecs would be outputted into the ``` codecs/src```  folder in the structure:

	- reference-model
	  - codecs
        - src
          - morphir
            - reference
                - model
                  - booksandrecords
                    - Codec.scala   <----- This is your genereated codec 
	- morphir.json
	- morphir-ir.json

The generated codecs ```Codec.scala```  has both encoders and decoders.

#### Importing and Using generated Codecs

In the example above the codecs where generated based on the ```BooksAndRecords.elm``` model and output in the codecs package. As an example lets say we want to use the generated codecs in a package called ```usecodecs``` with the following structure:

```
- usecodecs
  - src
     - UseCodecs.scala
        
```

Inside ```UseCodecs.scala``` we need to import the codecs from the package in which it was generated ie: ```morphir.reference.model.booksandrecords``` and use the codecs from the ```Codec``` object. Below is an example of how to export and use a codec.

```
import morphir.reference.model.booksandrecords.Codec._
import io.circe.Json._
import io.circe.parser._

object UseCodecs {
    def main(args: Array[Strings]): Unit = {
        val bookType = BookType("HardCover")
        val encodedBookType = encodeBookType(bookType)      <--- Using encoder
        
        val parseBookType = parse(encodedBookType.toString()).getOrElse(Null)
        val decodedBookType = decodeBookType(parseBookType.hcursor)        <--- Using decoder
    }
}

```
It is required to import ```io.circe.Json``` in the situation where you want to use methods from the ```circe``` library. Libraries such as ```io.circe.parser``` and ```io.circe.generic``` are usually used to work with encoders and decoders, you would need to add any additional library as a dependency to your project in order use them with the codecs.


#### Unsupported Features
Codecs are not generated for function types in the morphir ir.





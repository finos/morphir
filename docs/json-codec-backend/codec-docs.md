## Json Codec Backend
The purpose of this documentation is to give a explanation of how the Json Codec Backend works and how to use it.
The Json Codec backend is a tool that generates encoders and decoders from a Morphir IR using the Circe JSON library.

### How to use the JSON Codec Backend

The first step to using the JSON Codec backend is to add the Circe JSON library to your project. This can be done in two ways:
1. Add the Circe JSON dependency through your build tool eg. Sbt, Mill etc.
2. Add ```morphir-jvm``` as a dependency to your project.

#### Generating Codecs from the IR
The backend is built to generate codecs for only types so when generating an IR the ```-t``` which specifies ```--types-only``` flag should be used. Also, we want to add the ```-f``` flag to use the old CLI make function.

To generate Codecs from the  IR:
1. Run ```morphir-elm make -f -t``` to generate the IR.
2.  Run ```morphir-elm gen -s``` to generate the codecs
3.  In the situation where you do not have ```morphir-jvm``` as a dependency in your project, you have to add the ```-c``` flag to copy dependencies from the ```morphir-jvm``` project. Complete command for this is ```morphir-elm gen -s -c```

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


Running the command  ```morphir-elm gen -s -c -o codecs/src``` to generate codecs means your codecs would be outputted into the ``` codecs/src```  folder in the structure:

	- reference-model
	  - codecs
        - src
          - morphir
		    - booksandrecords
                  - Codec.scala   <----- This is your genereated codec 
	- morphir.json
	- morphir-ir.json

The generated codecs ```Codec.scala```  has both encoders and decoders. Encoders at the top and decoders following. This is a truncated example of how it looks:
```
package morphir.reference.model.booksandrecords  
  

object Codec{
	encoders ...
	
	decoders ...
}
```

In the example above ```myproject``` is the project in which the codecs would be used.
The codecs can now be imported into ```myproject```  and used.



#### Unsupported Features
Codecs are not generated for Function types in the morphir ir.





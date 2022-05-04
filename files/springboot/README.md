# morphir-elm SpringBoot generator

[Morphir](https://github.com/finos/morphir) is a multi-language system built on a data format that captures an 
application's domain model and business logic in a technology agnostic manner. This document will guide you on 
how to write your business logic in [Elm](https://elm-lang.org/), parse it into Morphir IR and transpile 
it to [Spring Boot](https://spring.io/projects/spring-boot/).

## Prerequisites

Morphir-elm package installed. Installation instructions: [morphir-elm installation](Readme.md)

If you make changes to the morphir-elm code, you should run

```
npm run build
``` 

## Translate Elm sources to Morphir IR

For detailed instructions refer to [morphir-elm installation](Readme.md).

Example:
If we have a file with module name defined as: 
```
module Morphir.Reference.Model.BooksAndRecords exposing (..)
```
**Important**: Currently, the Spring Boot generator works with custom types with at least one argument.

then our folder structure might be
```
exampleIR
|   morphir.json
|   |example
|   |   |Morphir
|   |   |   |Reference
|   |   |   |   |Model
|   |   |   |       BooksAndRecords.elm
```                 

The morphir.json file should be something like this

```
{
    "name": "Morphir.Reference.Model",
    "sourceDirectory": "example",
    "exposedModules": [

        "BooksAndRecords"
    ]
}  
```

Finally to translate to IR
- Go to command line
- Navigate to ExampleIR folder (where morphir.json is located)
- Execute
    ```
    morphir-elm make
    ```
A morphir-ir.json file should be generated with the IR content

## Transpil Morphir IR to a Spring Boot Project


- Run the following command

```
    morphir-elm gen -t SpringBoot -i [inputFile] -o [outputFolder]
```
where
- [inputFile] is path to the IR generated file. In the previous example should be: ``` exampleIR/morphir-ir.json ```
- [outputFolder] path where the Spring Boot project will be generated.
   
## Running the Spring Boot Project with Intellij

- Open the folder with Intellij
- It may ask to setup scala SDK
- Create a configuration of type "Spring Boot" in order to run the project
- The folder ```src/main/java``` should have the Scala source code files
- Run the application 
- Check that the server starts up without problems. If it has some errors, check if there are dependencies that should be added or changed.

## Running using command line

The project has the dependencies and configuration to be used with Maven (at least 3.6.2) and Java 8. The code is compatible with gradle but you should provide the gradle configuration files in order to run it.
- Install Maven
- Go to the generated project root directory
- Run ```mvn clean install```

It should create a target directory with a file with extension jar.
- Install java (tested with version 8)
- Go to the generated project root directory
- Run ```java -jar target\<filename>.jar```


## Connect to the Spring Boot application
### Swagger
Navigate to the base url ```http://localhost:8081``` and the swagger home page should appear

### Postman
- Open a REST API client (example: POSTMAN)
- Execute a POST operation ```http://localhost:8081/v1.0/command```

The code generator currently supports Jackson, the body of the POST operation should be
``` 
    {
    "type": "[commandsubclass]",
   "arg1": "[value1]",
   "arg2": "[value2]",
   ....}
```
```[commandsubtype]``` is a command sub class. Depending on the application how many arguments should be passed.

## Configuration
###Port

The port used with Maven is 8081, if you want to change it, modify the property
``` server.port = 8081 ``` in the application.properties file 


```
<generated root folder>
|   src
|   |main
|   |   |java
|   |   |resources
|   |   |   |application.properties
```

## Metrics
Metrics are available at the url ```http://localhost:8081/metrics ``` .
You can check ```https://www.dropwizard.io``` for more information

## License

Copyright 2014 Morgan Stanley

Distributed under the [Apache License, Version 2.0](http://www.apache.org/licenses/LICENSE-2.0).

SPDX-License-Identifier: [Apache-2.0](https://spdx.org/licenses/Apache-2.0)

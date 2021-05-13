**This document will describe how we can use Insight API into any UI.**

## Prerequisites
Morphir-elm package installed. Installation instructions: [morphir-elm installation](https://github.com/finos/morphir-elm/blob/master/README.md)

If you make changes to the morphir-elm code, you should run

```
npm run build
``` 
## Translate Elm sources to Morphir IR
For detailed instructions refer to [morphir-elm installation](https://github.com/finos/morphir-elm/blob/master/README.md)

Example:
If we have a file with module name defined as:
```
module Morphir.Reference.Model.Insight.UseCase1 exposing (..)
```

then our folder structure might be
```
exampleIR
|   morphir.json
|   |example
|   |   |Morphir
|   |   |   |Reference
|   |   |   |   |Model
|   |   |   |   |     |Insight
|   |   |   |   |     |       UseCase1
```                 

The morphir.json file should be something like this

```
{
    "name": "Morphir.Reference.Model",
    "sourceDirectory": "example",
    "exposedModules": [
        "Insight.UseCase1"
    ]
}  
```
**Note** Every folder in Model directory will contribute to exposed module name.

Finally, to translate to IR
- Go to command line
- Navigate to ExampleIR folder (where morphir.json is located)
- Execute
    ```
    morphir-elm make
    ```
A morphir-ir.json file should be generated with the IR content


## How to use API in UI
1. After completing all the prerequisites include the `insight.js` file into your UI. An actual path :
```
    node_modules/morphir-elm/cli/web/insight.js
```
2. If you wanted to use this file into HTML file :
```
    <script src="node_modules/morphir-elm/cli/web/insight.js"></script>
```
3. Now you just need to communicate with elm architecture using javascript.
For more details on interoperability [JavaScript Interoperability ](https://guide.elm-lang.org/interop).
**Note** - Every code below this must be either in javascript file or inside script tags.
### Initialise it with Flags
```
   var app = Elm.Morphir.Web.Insight.init({
   node: document.getElementById('app'),
   flags: {  distribution : distribution 
          ,  config : { fontSize : 12 , decimalDigit : 2 }
          }
   });
```
 - Distribution field in the flag is same what we are getting from morphir-ir.json file. You can host this file on a server and then make an HTTP request to get the file data in JSON format. Store the JSON request into a variable(Name - distribution) and simply pass it in distribution field.
 - Config field is used to take the control over styling part. Padding and spacing between elements will adjust accordingly when you change the font size. Here, decimalDigit is used to set precision of numbers. You can simply skip any of these field if you don't want.Then these fields will initialize with default values fontSize = 12 and decimalDigit = 2.
   
For more details on flags [Flags](https://guide.elm-lang.org/interop/flags.html)

### Send Function Name threw ports
- Function name should be pass as combination of exposed module name + local name.
- If your exposed module is `Insight.UseCase1` and it contains a local function with name `limitTracking`. Pass both separated by a colon `:`
```
    app.ports.receiveFunctionName.send("Insight.UseCase1:limitTracking")
```
        
For more details on ports [Ports](https://guide.elm-lang.org/interop/ports.html)

### Send Function Arguments for a path highlighting
- Sending arguments is a bit complex because you need to encode it first. But we are working parallelly to reduce the complexity of encoding. 
- You need to send type information of arguments along with its values otherwise it won't be accepted.
- If function signature is :
``` 
    limitTracking : Float -> Float -> Float -> Float -> Float -> List TrackingAdvantage
```
- It means it is expecting 5 arguments of float type and returning a List of TrackingAdvantage type.
``` 
    var argsList = [10 ,13 ,-16 ,15 ,-10];
    app.ports.receiveFunctionArguments.send(argsList);
```
- For more details of encoding like how to encode `list, tuple, and record`
[Encoding Decoding File](https://github.com/finos/morphir-elm/blob/master/src/Morphir/IR/Type/DataCodec.elm)
- This file has all the functions of encoding and decoding of elm data types.
  
- For better understanding of json mapping from elm to json refer the below file. 
[Json Mapping](https://github.com/finos/morphir-elm/blob/master/docs/json-mapping.md)

### Example File
- If you are still confused like how to write code for all that steps, you can have a look at example file.
[Insight API Example File](https://github.com/finos/morphir-elm/blob/master/cli/web/insight.html).

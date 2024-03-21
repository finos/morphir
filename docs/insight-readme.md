---
id: insight-api-guide
---

# Insight API Guide
The purpose of this document is how we can use Insight API into any UI.

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
After including the above script file in your code, you can decide between the two below ways of including Insight in your project.

### Initilazing the Elm App directly
You just need to communicate with elm architecture using javascript.
For more details on interoperability [JavaScript Interoperability ](https://guide.elm-lang.org/interop).
**Note** - Every code below this must be either in javascript file or inside script tags.
#### Initialise it with Flags
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

#### Send Function Name through ports
- Function name should be pass as combination of exposed module name + local name.
- If your exposed module is `Insight.UseCase1` and it contains a local function with name `limitTracking`. Pass both separated by a colon `:`
```
    app.ports.receiveFunctionName.send("Insight.UseCase1:limitTracking")
```
        
For more details on ports [Ports](https://guide.elm-lang.org/interop/ports.html)

#### Send Function Arguments for a path highlighting
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


### Web component
You can also achieve the above functionality using the included ```<morphir-insight>...<\morphir-insight>``` custom web component, which has two input attributes, `fqn` and `arguments`, for the fully qualified name of the function you wish to dispaly, and the the list of inputs (just like in the above method).
#### Initializing the web component
After including the above tag, it's the developers responsibility to call the provided `.init` function on the web component, which expects a valid Morphir IR distribution in a JSON string format. This init function can be called any time after the HTML has been rendered, and will initialize the web component.

### Limitations

Due to inherent limitations stemming from Elm's architecture and design philosphy (total encapsulation of the elm runtime to be able to guarantee no runtime errors), you can't pass values by reference through the port functions. In our case this means that each time an Insight instance is initialized, a new copy of the Morphir IR is added to the Javascript heap. Developers should be mindful of this, as creating multiple Insights with larger IRs has the possibility to be prohibitively memory intensive.

### Example File
- If you are still confused like how to write code for all that steps, you can have a look at example file.
[Insight API Example File](https://github.com/finos/morphir-elm/blob/master/cli/web/insight.html).

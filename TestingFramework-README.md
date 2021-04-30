**This document will describe how we can use Testing Framework within developer server**

## Prerequisites
- Morphir-elm package installed. Installation instructions: [morphir-elm installation](https://github.com/finos/morphir-elm/blob/master/README.md)
- Translate elm source into Morphir IR
- The function which you wanted to test using this framework must be present into the Morphir IR.

## How to use this framework
1. Create a file name `morphir-tests.json` if not present and put it into the same directory where `morphir.json` and `morphir-ir.json` file is present.
- This file is a dictionary with key as fully qualified name of function and value as list of testcases.
-  A testcase structure looks like this
``` 
   type alias TestCase =
   { inputs : List RawValue
   , expectedOutput : RawValue
   , description : String
   }
```

Example:
If we have a file with module name defined as:
```
module Morphir.Reference.Model.Issues.Issue410 exposing (..)
```

then our folder structure might be
```
exampleIR
|   morphir.json
|   |example
|   |   |Morphir
|   |   |   |Reference
|   |   |   |   |Model
|   |   |   |   |     |Issues
|   |   |   |   |     |       Issue410
```

- `Issue410` file has a function name `addFunction` which takes 2 Int values and return 1 Int value.
```
   addFunction : Int -> Int -> Int
```

a) FQName for function
- `FQName` is a tuple of packagePath modulePath localName which describe the complete address of a function.
- `PackagePath` is complete path of Model directory from the directory where morphir.json file is present.
- `ModulePath` is complete path of file from Model directory.
- `LocalName` is function name within file itself.
- You can look at `morphir.json` file for better understanding of FQName where name is `packagePath` and exposedModule is `modulePath` for each elm source file.
```
    [ [ [ "morphir" ], [ "reference" ], [ "model" ] ]
    , [ [ "issues" ], [ "issue", "410" ] ]
    , [ "add", "function" ]
    ]
```

b) Sample testcase for function
- `inputs` will always be a list. Values inside list could be Int, float, record, list , tuple or anything.
- `expectedOutput` depends on the return type of the function. Like wise Input it could also be anything.
- `description` is a string in case you wanted to add any description for a testcase.
```
    { "inputs" : [ 4 , 5 ]
    , "expectedOutput" : 9
    , "description" : "Add"
    }
```

- For more details of encoding like how to encode `list, tuple, and record`
  [Encoding Decoding File](https://github.com/finos/morphir-elm/blob/master/src/Morphir/IR/Type/DataCodec.elm)
- This file has all the functions of encoding and decoding of elm data types.

c) Create a json object from FQName and Testcases
```
[
  [
    [ [ [ "morphir" ], [ "reference" ], [ "model" ] ]
    , [ [ "issues" ], [ "issue", "410" ] ]
    , [ "add", "function" ]
    ]
  ,
    [
      {
        "inputs" : [ 4 , 5 ],
        "expectedOutput" : 9,
        "description" : "Add"
      },
      {
        "inputs" : [ 14 , 15 ],
        "expectedOutput" : 29,
        "description" : "Add"
      },
      {
        "inputs" : [ 10 , 1 ],
        "expectedOutput" : 11,
        "description" : "Add"
      },
      {
        "inputs" : [ -10 , 1 ],
        "expectedOutput" : -9,
        "description" : "Add"
      }
    ]
  ]
]
```

2. Run the server into that directory where morphir.json file is present.
```
   morphir-elm develop  
```

3. Run the developer server into the root directory
```
   npm run dev-server-live
```

4. You need to call this API with a specific URL
- Structure of URL http://localhost:8000/function/packagePath:modulePath:localName
- Sample URL for Testing TestSuites
```
   http://localhost:8000/function/Morphir.Reference.Model:Issues.Issue410:addFunction
```

5. Easy Debugging
- This framework also allows user to match actual output with expected output.
- If the actual output will be in green color then it matches otherwise it would be red.
- It also shows the error if interpreter is unable to evaluate your inputs.
  
## Example
- Output is not matching 

![TestCase-1](./assets/TestCase1.PNG)
- Output is matching
  
![TestCase-2](./assets/TestCase2.PNG)
  

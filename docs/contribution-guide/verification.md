# Verification Instructions

The purpose of this document is to provide a detailed explanation of how to verify a new released version of ```morphir-elm```. The following instructions are to be followed after every release in order to make sure that the release is valid.

### Who this Guide is Designed For
1. Business users of Morphir who would want to update the morphir-elm version to the latest release
2. Developers who would want to verify the validity of a release

### Upgrading ```morphir-elm``` to the latest version

- Run ```npm install morphir-elm``` to upgrade to the latest version. This is the only step you need as a business user to upgrade to a new release of ```morphir-elm```

### Verifying a ```morphir-elm``` release 

After upgrade, a series of command must be run on a model to verify the release, below are steps to create a minimal model.

#### Creating a Model
This is to create a sample model to  validate the relase. The sample model is called ```schedule```

Create a directory:
```
mkdir schedule
cd schedule    
```

Next setup the Morphir project and configuration file, morphir.json
```
mkdir src
echo '{ "name": "Morphir.Example.App", "sourceDirectory": "src", "exposedModules": [ ] }' > morphir.json
```

Let's create the Elm file we would be working with
```
mkdir src/Morphir
mkdir src/Morphir/Example
touch src/Morphir/Example/Schedule.elm
```

Next update the ```morphir.json```  to reflect the current module.

```
{
    "name": "Morphir.Example",
    "sourceDirectory": "src",
    "exposedModules": [
        "Schedule"
    ]
}
```

Finally, to finish up the model paste the following logic in Schedule.elm

```
module Morphir.Example.Schedule exposing (..)


type Days
    = Friday
    | Saturday
    | Sunday


plan : Days -> String
plan days =
    case days of
        Friday ->
            "Practice for all drivers"

        Saturday ->
            "Qualifying day"

        Sunday ->
            "Race day!"      

```

Now we have minimal model to run commands on. Run the following commands to verify a release. 

- Run ```Run morphir-elm make``` to verify that an IR(```morphir-ir.json```) is created.
- Create ```morphir-tests.json``` in the same directory as ```morphir-ir.json```. This would contain tests generated from the Morphir Develop UI.
- Run ```morphir-elm develop -o localhost``` and in your browser navigate to ```http://localhost:3000``` to access the UI
- Run ```morphir-elm gen``` to generate target code




## Rollback Instructions




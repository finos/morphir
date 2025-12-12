---
id: publishing-elm-package
---

This document describes how maintainers can push new releases of `morphir-elm` into NPM and the Elm package repo. 

# Publishing the Elm package

The latest elm tooling (0.19.1) has some [issues with large docs](https://github.com/elm/compiler/issues?q=is%3Aissue+is%3Aopen+loading+docs) which impacts `finos/morphir-elm`. Because of this we had to turn-off the automation so the publishing can only be done manually by a maintainer.

Here are the steps:

1. Clone the `finos/morphir-elm` repo to a local workspace. Make sure that it's not a clone of your fork but a clone of the main repo.
2. Make sure that the clone is up-to-date and you are on the `main` branch.
3. Run `elm bump`.
4. If this fails with the `PROBLEM LOADING DOCS` error you will have to use an older version of Elm. 
5. You can install the previous version using `npm install -g elm@0.19.0-no-deps`.
6. Run `elm bump` again.
7. This will update the `elm.json` so you need to add an commit it:
    - `git add elm.json`
    - `git commit -m "Bump Elm package version"`
8. Now you need to create a tag that matches the Elm package version:
    - `git tag -a <elm_package_version> -m "new Elm package release"`
    - `git push origin <elm_package_version>`
9. Now you are ready to publish the Elm package:
    - `elm publish`    


# Publishing the NPM package

1. Clone the `finos/morphir-elm` github repo or pull the latest from the master branch if you have a clone already.
    ```
    git clone https://github.com/finos/morphir-elm.git
    ```
   or
    ```
    git pull origin master
    ```
2. Build the CLI.
    ```
    npm run build
    ```
3. Run `np` for publishing.
   - If you don't have `np` installed yet, install it with `npm install -g np`
4. `np` will propmpt you to select the next semantic version number so you'll have to decide if your changes are major, minor or patch.
   - **Note**: `np` might say that there has not been any commits. This is normal if you just published the Elm package since it picks up
     the tag from that one. It is safe to respond `y` to that question because the rest of the process will use the version number from the
     `package.json` and push a tag with a prefix `v` so it does not collide with Elm which does not use a prefix.
5. `np` will also ask you for credentials.

# Verification Instructions

The purpose of this document is to provide a detailed explanation of how to verify a new released version of ```morphir-elm```. The following instructions are to be followed after every release in order to make sure that the release is valid.

### Who this Guide is Designed For
1. Business users of Morphir who would want to update the morphir-elm version to the latest release
2. Developers who would want to verify the validity of a release

### Upgrading ```morphir-elm``` to the latest version

- Run ```npm install morphir-elm``` to upgrade to the latest version. This is the only step you need as a business user to upgrade to a new release of ```morphir-elm```

### Verifying a ```morphir-elm``` release

After upgrade, a series of commands must be run on a model to verify the release, below are steps to create a minimal model.

#### Creating a Model
This is to create a sample model to  validate the release. The sample model is called ```schedule```

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

Next create the Elm file we would be working with
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


plan : String -> String
plan day =
    "Work Day"
    
```

Now we have minimal model to run commands on. Run the following commands to verify a release.

- Run ```Run morphir-elm make``` to verify that an IR(```morphir-ir.json```) is created.
   - Use the ```-o,--output``` flag to specify the location where the Morphir IR will be saved (default: ```morphir-ir.json```)
   - Use ```-p,--project-dir``` flag to specify the root directory where the ```morphir.json``` is located.
- Create ```morphir-tests.json``` in the same directory as ```morphir-ir.json```. This would contain tests generated from the Morphir Develop UI.
- Run ```morphir-elm develop -o localhost``` and in your browser navigate to ```http://localhost:3000``` to access the UI
- Create and save tests using the Morphir develop UI
- Run ```morphir-elm test``` tests in your terminal to validate that all tests pass.

- Run ```morphir-elm gen``` to generate target code. Default code generated is Scala. To change the target language generated use the ```-t``` option. Eg. ```morhir-elm gen -t TypeScript```.
- Run ```morphir-elm gen -c true``` to copy the dependencies used by the generated code to the output path
- Run ```morphir-stats``` to generate feature statistics. This command generates a folder ```stats``` which contains information about features available in the IR


## Rollback Instructions

In the case where an invalid version is published , the developer has to rollback to a previous working version on npm. This involves changing the ```latest``` tag on npm to point to a previous working version.


- Go to [Morphir Elm](https://www.npmjs.com/package/morphir-elm) , click on the versions tab. The last working version is usually a version behind the latest version released. You can find version numbers under ```Version History```

- Run the command ```npm dist-tag add morphir-elm@<version> latest```

This command tags the version specified as the ```latest```



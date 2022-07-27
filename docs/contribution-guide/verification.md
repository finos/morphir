# Verification Instructions

The purpose of this document is to provide a detailed explanation of how to verify a new released version of ```morphir-elm```. The following instructions are to be followed after every release in order to make sure that the release is valid.

### Who this Guide is Designed For
1. Business users of Morphir who would want to update the morphir-elm version to the latest release
2. Developers who would want to verify the validity of a release

### Upgrading ```morphir-elm``` to the latest version

- Run ```npm install morphir-elm``` to upgrade to the latest version. This is the only step you need as a business user to upgrade to a new release of ```morphir-elm```

### Verifying a ```morphir-elm``` release 

After upgrade run the following commands to verify a release. The model to use as input can be found at ```morphir-elm\tests-integration\reference-model```.

- Run ```Run morphir-elm make``` to verify that an IR(```morphir-ir.json```) is created.
- Read instructions from  [Testing Framework](https://github.com/klahnunya/morphir-elm/blob/main/docs/developers-guide/files/TestingFramework-README.md) to run tests on the model.
- Run ```morphir-elm gen``` to generate target code

Read the following documentation [Morphir Elm Commands](https://github.com/klahnunya/morphir-elm/blob/main/docs/developers-guide/files/morphir-elm-commands-processing.md) to know options available on above-mentioned commands.


## Rollback Instructions




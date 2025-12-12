---
id: scala-backend
sidebar_position: 1
---


# Scala Backend
The Scala backend takes the Morphir IR as the input and returns an in-memory
representation of files generated - FileMap
The consumer is responsible for getting the input IR and saving the output to the file-system.

The transformation from the Morphir IR to the FileMap is based on the Scala AST.\\
[1. Reading the Input IR](#) \
[2. Scala Code Generation](#)\
[3. Writing Output to File System](#)

## **1. Reading Input IR**
The IR is saved on disk as JSON formatted file, morphir-ir.json.
The IR (as Json) and command line option is passed to Elm through port:
```
worker.ports.generate.send([options, ir])
```
The file is received in the CLI.elm and decoded into a Decode Value.

```
    targetOption =
        Decode.decodeValue (field "target" string) optionsJson

    optionsResult =
        Decode.decodeValue (decodeOptions targetOption) optionsJson

    packageDistroResult =
        Decode.decodeValue DistributionCodec.decodeVersionedDistribution packageDistJson

```
The packageDistroResult is a _Morphir.IR.Distribution_ type which is an in memory representation of the IR.

The distribution is passed to the Scala backend to generate a FileMap
```                        
fileMap =
   mapDistribution options enrichedDistro
```
The code generation phase consists of  functions that transform the distribution into a FileMap


\

## **2. Code Generation**
The code generation consists of a number of mapping functions that map the Morphir IR types to Scala Types.

#### mapDistribution
This is the entry point for the Scala backend. This function take Morphir IR
(as a Distribution type) and generates the FileMap of Scala Source codes.
A FileMap is a Morphir type and is a dictionary of File path and file content.

\
#### mapPackageDefinition
This function takes the Distribution, Package path and Package definition
and returns a FileMap.
This function maps through the modules in the package definition and for each module, it
generate a compilation unit for each module by calling the PrettyPrinter.mapCompilationUnit 
which returns a compilation unit. \
A compilation unit is a record type with the following fields
\\

```
type alias CompilationUnit =
    { dirPath : List String
    , fileName : String
    , packageDecl : PackageDecl
    , imports : List ImportDecl
    , typeDecls : List (Documented (Annotated TypeDecl))
    }
```

\

#### mapFQNameToPathAndName
Takes a Morphir IR fully-qualified name and maps it to tuple of Scala path and name.
A fully qualified name consists of packagPath, modulePath and localName.

\

#### mapFQNameToTypeRef
Maps a Morphir IR fully-qualified name to Scala type reference. It extracts the path and name
from the fully qualified name and uses the Scala.TypeRef constructor to create a Scala Reference
type.
```
mapFQNameToTypeRef : FQName -> Scala.Type
mapFQNameToTypeRef fQName =
    let
        ( path, name ) =
            mapFQNameToPathAndName fQName
    in
    Scala.TypeRef path (name |> Name.toTitleCase)
```

\

#### mapTypeMember
This function maps a type declaration in Morphir to a Scala member declaration.

\

#### mapModuleDefinition
This function maps a module definition to a list of Scala compilation units.

\

#### mapCustomTypeDefinition
Maps a custom type to a List of Scala member declaration

\

#### mapType
Maps a Morphir IR Type to a Scala type

\


#### mapFunctionBody
Maps an IR value defintion to a Scala value.

\


#### mapValue
Maps and IR Value type to a Scala value.

\


#### mapPattern
Maps an IR Pattern type to a Scala Pattern type

\


#### mapValueName
Maps an IR value name (List String) to a Scala value (String)

#### scalaKeywords
A set of Scala keywords that cannot be used as a variable name.

\


#### javaObjectMethods
We cannot use any method names in `java.lang.Object` because values are represented as functions/values in a Scala
object which implicitly inherits those methods which can result in name collisions.

\


#### uniqueVarName

\


## **3. Saving Generated Files**
The Scala backend returns a FileMap to the Typescript CLI. 
The fileMap returned from the backend is encoded into Json and send through the generateResult port.

```
    ...
    ...
    fileMap =
        mapDistribution options enrichedDistro
in
( model, fileMap 
    |> Ok 
    |> encodeResult Encode.string encodeFileMap 
    |> generateResult )
```

The generated FileMap is received in the JavaScript and parsed into a string.
```
const fileMap = await generate(opts, JSON.parse(morphirIrJson.toString()))
```

Finally, the returned files are written to disk. The complete gen() function is given below:
```
async function gen(input, outputPath, options) {
    await mkdir(outputPath, {
        recursive: true
    })
    const morphirIrJson = await readFile(path.resolve(input))
    const opts = options
    opts.limitToModules = options.modulesToInclude ? options.modulesToInclude.split(',') : null
    const fileMap = await generate(opts, JSON.parse(morphirIrJson.toString()))

    const writePromises =
        fileMap.map(async ([
            [dirPath, fileName], content
        ]) => {
            const fileDir = dirPath.reduce((accum, next) => path.join(accum, next), outputPath)
            const filePath = path.join(fileDir, fileName)
            if (await fileExist(filePath)) {
                console.log(`UPDATE - ${filePath}`)
            } else {
                await mkdir(fileDir, {
                    recursive: true
                })
                console.log(`INSERT - ${filePath}`)
            }
            if (options.target == 'TypeScript') {
                return fsWriteFile(filePath, prettier.format(content, { parser: "typescript" }))
            } else {
                return fsWriteFile(filePath, content)
            }
        })
    const filesToDelete = await findFilesToDelete(outputPath, fileMap)
    const deletePromises =
        filesToDelete.map(async (fileToDelete) => {
            console.log(`DELETE - ${fileToDelete}`)
            return fs.unlinkSync(fileToDelete)
        })
    copyRedistributables(options, outputPath)
    return Promise.all(writePromises.concat(deletePromises))
}

```

Note: Generated files overwrite existing directory and contents
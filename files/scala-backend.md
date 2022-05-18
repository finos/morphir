# Scala Backend
The Scala backend takes the Morphir IR as the input and returns an in-memory
representation of files generated - FileMap
The consumer is responsible for getting the input IR and saving the output to the file-system.

The transformation from the Morphir IR to to the FileMap is based on the Scala AST.


**mapDistribution**
This is the entry point for the Scala backend. This function take Morphir IR
(as a Distribution type) and generates the FileMap of Scala Source codes.
A FileMap is a Morphir type and is a dictionary of File path and file content.


**mapPackageDefinition**
This function takes the Distribution, Package path and Package definition
and returns a FileMap


**mapFQNameToPathAndName**
Takes a Morphir IR fully-qualified name and maps it to tuple of Scala path and name


**mapFQNameToTypeRef**
Maps a Morphir IR fully-qualified name to Scala reference.


**mapTypeMember**
This function maps a type declaration in Morphir to a Scala member declaration.


**mapModuleDefinition**
This function maps a module definition to a list of Scala compilation units.


**mapCustomTypeDefinition**
Maps a custom type to a List of Scala member declaration

**mapType**
Maps a Morphir IR Type to a Scala type

**mapFunctionBody**
Maps an IR value defintion to a Scala value.

**mapValue**
Maps and IR Value type to a Scala value.


**mapPattern**
Maps an IR Pattern type to a Scala Pattern type


**mapValueName**
Maps an IR value name (List String) to a Scala value (String)

**scalaKeywords**
A set of Scala keywords that cannot be used as a variable name.

**javaObjectMethods**
We cannot use any method names in `java.lang.Object` because values are represented as functions/values in a Scala
object which implicitly inherits those methods which can result in name collisions.

**uniqueVarName**


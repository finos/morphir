module Morphir.Scala.Backend exposing (..)

import Dict
import Morphir.File.FileMap exposing (FileMap)
import Morphir.IR.AccessControlled exposing (Access(..), AccessControlled)
import Morphir.IR.Module as Module
import Morphir.IR.Name as Name
import Morphir.IR.Package as Package
import Morphir.IR.Path exposing (Path)
import Morphir.Scala.AST as Scala
import Morphir.Scala.PrettyPrinter as PrettyPrinter
import Set exposing (Set)


type alias Options =
    { targetPackage : List String
    }


mapPackageDefinition : Options -> Package.Definition a -> FileMap
mapPackageDefinition opt packageDef =
    packageDef.modules
        |> Dict.toList
        |> List.concatMap
            (\( modulePath, moduleImpl ) ->
                mapModuleDefinition opt packageDef modulePath moduleImpl
                    |> List.map
                        (\compilationUnit ->
                            let
                                fileContent =
                                    compilationUnit
                                        |> PrettyPrinter.mapCompilationUnit (PrettyPrinter.Options 2 80)
                            in
                            ( ( compilationUnit.dirPath, compilationUnit.fileName ), fileContent )
                        )
            )
        |> Dict.fromList


mapModuleDefinition : Options -> Package.Definition a -> Path -> AccessControlled (Module.Definition a) -> List Scala.CompilationUnit
mapModuleDefinition opt packageDef modulePath accessControlledModuleDef =
    let
        ( packagePath, moduleName ) =
            case modulePath |> List.reverse of
                [] ->
                    ( [], [] )

                lastName :: reverseModulePath ->
                    ( reverseModulePath |> List.reverse, lastName )

        typeMembers : List Scala.MemberDecl
        typeMembers =
            accessControlledModuleDef.value.types
                |> Dict.toList
                |> List.concatMap
                    (\( typeName, accessControlledTypeDef ))

        --recordTypeAliasUnits =
        --    impl.typeAliases
        --        |> Dict.toList
        --        |> List.map
        --            (\( typeName, typeDecl ) ->
        --                { dirPath = modulePath |> List.map (Name.toCamelCase >> String.toLower)
        --                , fileName = (typeName |> Name.toTitleCase) ++ ".scala"
        --                , packageDecl = modulePath |> List.map (Name.toCamelCase >> String.toLower)
        --                , imports = []
        --                , typeDecls = Types.mapRecordTypeAlias typeName typeDecl
        --                }
        --            )
        --
        --typeAliasUnit =
        --    { dirPath = modulePath |> List.map (Name.toCamelCase >> String.toLower)
        --    , fileName = "package.scala"
        --    , packageDecl = packagePath |> List.map (Name.toCamelCase >> String.toLower)
        --    , imports = []
        --    , typeDecls =
        --        [ Scala.Object
        --            { modifiers = [ Scala.Package ]
        --            , name = moduleName |> Name.toCamelCase |> String.toLower
        --            , members =
        --                impl.typeAliases
        --                    |> Dict.toList
        --                    |> List.filterMap
        --                        (\( typeName, typeDecl ) ->
        --                            case typeDecl.exp of
        --                                -- Do not generate type alias for record types because they will be represented by case classes
        --                                T.Record _ ->
        --                                    Nothing
        --
        --                                -- Do not generate type alias for native types
        --                                T.Constructor ( [ [ "slate", "x" ], [ "core" ], [ "native" ] ], [ "native" ] ) _ ->
        --                                    Nothing
        --
        --                                _ ->
        --                                    Just
        --                                        (Scala.TypeAlias
        --                                            { alias = typeName |> Name.toTitleCase
        --                                            , typeArgs = typeDecl.params |> List.map (T.Variable >> Types.mapExp)
        --                                            , tpe = Types.mapExp typeDecl.exp
        --                                            }
        --                                        )
        --                        )
        --            , extends = []
        --            }
        --        ]
        --    }
        --
        --unionTypeUnits =
        --    impl.unionTypes
        --        |> Dict.toList
        --        |> List.map
        --            (\( typeName, typeDecl ) ->
        --                { dirPath =
        --                    modulePath |> List.map (Name.toCamelCase >> String.toLower)
        --                , fileName =
        --                    (typeName |> Name.toTitleCase) ++ ".scala"
        --                , packageDecl =
        --                    modulePath |> List.map (Name.toCamelCase >> String.toLower)
        --                , imports =
        --                    []
        --                , typeDecls =
        --                    Types.mapUnionType modulePath typeName typeDecl
        --                }
        --            )
        moduleUnit : Scala.CompilationUnit
        moduleUnit =
            { dirPath = List.append opt.targetPackage (packagePath |> List.map (Name.toCamelCase >> String.toLower))
            , fileName = (moduleName |> Name.toTitleCase) ++ ".scala"
            , packageDecl = List.append opt.targetPackage (packagePath |> List.map (Name.toCamelCase >> String.toLower))
            , imports = []
            , typeDecls =
                [ Scala.Object
                    { modifiers =
                        case accessControlledModuleDef.access of
                            Public ->
                                []

                            Private ->
                                [ Scala.Private (opt.targetPackage |> List.reverse |> List.head) ]
                    , name =
                        moduleName |> Name.toTitleCase
                    , members = []

                    --accessControlledModuleDef.value.values
                    --    |> Dict.toList
                    --    |> List.map
                    --        (\( name, accessControlledValue ) ->
                    --            let
                    --                scalaName =
                    --                    name |> Name.toCamelCase
                    --
                    --                normalizedName =
                    --                    if reservedValueNames |> Set.member scalaName then
                    --                        "_" ++ scalaName
                    --
                    --                    else
                    --                        scalaName
                    --
                    --                ( scalaValue, scalaReturnType ) =
                    --                    case impl.valueTypes |> Dict.get name of
                    --                        Just valueType ->
                    --                            let
                    --                                valueWithTypeOrError =
                    --                                    TypeInferencer.checkPackage packageDef valueType accessControlledValue
                    --                            in
                    --                            ( valueWithTypeOrError |> Values.mapExp, valueType |> Types.mapExp |> Just )
                    --
                    --                        Nothing ->
                    --                            let
                    --                                valueWithTypeOrError =
                    --                                    TypeInferencer.inferPackage packageDef accessControlledValue
                    --
                    --                                maybeValueType =
                    --                                    valueWithTypeOrError
                    --                                        |> A.annotation
                    --                                        |> Result.toMaybe
                    --                            in
                    --                            ( valueWithTypeOrError |> Values.mapExp, maybeValueType |> Maybe.map Types.mapExp )
                    --            in
                    --            Scala.FunctionDecl
                    --                { modifiers = []
                    --                , name = normalizedName
                    --                , typeArgs =
                    --                    let
                    --                        extractedTypeArgNames =
                    --                            impl.valueTypes
                    --                                |> Dict.get name
                    --                                |> Maybe.map List.singleton
                    --                                |> Maybe.withDefault []
                    --                                |> Types.extractTypeArgNames
                    --                    in
                    --                    extractedTypeArgNames
                    --                        |> List.map (T.Variable >> Types.mapExp)
                    --                , args = []
                    --                , returnType =
                    --                    impl.valueTypes
                    --                        |> Dict.get name
                    --                        |> Maybe.map Types.mapExp
                    --                , body =
                    --                    Just scalaValue
                    --                }
                    --        )
                    , extends = []
                    }
                ]
            }
    in
    [ moduleUnit ]


reservedValueNames : Set String
reservedValueNames =
    Set.fromList
        -- we cannot use any method names in java.lamg.Object because values are represented as functions/values in a Scala object
        [ "clone"
        , "equals"
        , "finalize"
        , "getClass"
        , "hashCode"
        , "notify"
        , "notifyAll"
        , "toString"
        , "wait"
        ]

module Morphir.Scala.Backend exposing (..)

import Dict
import Morphir.File.FileMap exposing (FileMap)
import Morphir.IR.AccessControlled exposing (Access(..), AccessControlled)
import Morphir.IR.FQName exposing (FQName(..))
import Morphir.IR.Module as Module
import Morphir.IR.Name as Name
import Morphir.IR.Package as Package
import Morphir.IR.Path as Path exposing (Path)
import Morphir.IR.Type as Type exposing (Type)
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


mapFQNameToTypeRef : FQName -> Scala.Type
mapFQNameToTypeRef (FQName packagePath modulePath localName) =
    let
        scalaModulePath =
            case modulePath |> List.reverse of
                [] ->
                    []

                lastName :: reverseModulePath ->
                    List.append (List.append (packagePath |> List.map (Name.toCamelCase >> String.toLower)) (reverseModulePath |> List.reverse |> List.map (Name.toCamelCase >> String.toLower))) [ lastName |> Name.toTitleCase ]
    in
    Scala.TypeRef scalaModulePath (localName |> Name.toTitleCase)


mapModuleDefinition : Options -> Package.Definition a -> Path -> AccessControlled (Module.Definition a) -> List Scala.CompilationUnit
mapModuleDefinition opt packageDef modulePath accessControlledModuleDef =
    let
        currentPackagePath =
            [ [ "morphir" ] ]

        ( scalaPackagePath, moduleName ) =
            case modulePath |> List.reverse of
                [] ->
                    ( [], [] )

                lastName :: reverseModulePath ->
                    ( List.append (currentPackagePath |> List.map (Name.toCamelCase >> String.toLower)) (reverseModulePath |> List.reverse |> List.map (Name.toCamelCase >> String.toLower)), lastName )

        typeMembers : List Scala.MemberDecl
        typeMembers =
            accessControlledModuleDef.value.types
                |> Dict.toList
                |> List.concatMap
                    (\( typeName, accessControlledDocumentedTypeDef ) ->
                        case accessControlledDocumentedTypeDef.value.value of
                            Type.TypeAliasDefinition typeParams typeExp ->
                                []

                            Type.CustomTypeDefinition typeParams accessControlledCtors ->
                                List.map Scala.MemberTypeDecl
                                    (List.concat
                                        [ [ Scala.Trait
                                                { modifiers = [ Scala.Sealed ]
                                                , name = typeName |> Name.toTitleCase
                                                , typeArgs = typeParams |> List.map (Name.toTitleCase >> Scala.TypeVar)
                                                , extends = []
                                                , members = []
                                                }
                                          ]
                                        , accessControlledCtors.value
                                            |> List.map
                                                (\(Type.Constructor ctorName ctorArgs) ->
                                                    Scala.Class
                                                        { modifiers = [ Scala.Case ]
                                                        , name = ctorName |> Name.toTitleCase
                                                        , typeArgs = typeParams |> List.map (Name.toTitleCase >> Scala.TypeVar)
                                                        , ctorArgs =
                                                            ctorArgs
                                                                |> List.map
                                                                    (\( argName, argType ) ->
                                                                        { modifiers = []
                                                                        , tpe = mapType argType
                                                                        , name = argName |> Name.toCamelCase
                                                                        , defaultValue = Nothing
                                                                        }
                                                                    )
                                                                |> List.singleton
                                                        , extends =
                                                            let
                                                                parentTraitRef =
                                                                    mapFQNameToTypeRef (FQName currentPackagePath modulePath typeName)
                                                            in
                                                            if List.isEmpty typeParams then
                                                                [ parentTraitRef ]

                                                            else
                                                                [ Scala.TypeApply parentTraitRef (typeParams |> List.map (Name.toTitleCase >> Scala.TypeVar)) ]
                                                        }
                                                )
                                        ]
                                    )
                    )

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
            { dirPath = scalaPackagePath
            , fileName = (moduleName |> Name.toTitleCase) ++ ".scala"
            , packageDecl = scalaPackagePath
            , imports = []
            , typeDecls =
                [ Scala.Documented (Just (String.join "" [ "Generated based on ", modulePath |> Path.toString Name.toTitleCase "." ])) <|
                    Scala.Object
                        { modifiers =
                            case accessControlledModuleDef.access of
                                Public ->
                                    []

                                Private ->
                                    [ Scala.Private (opt.targetPackage |> List.reverse |> List.head) ]
                        , name =
                            moduleName |> Name.toTitleCase
                        , members =
                            typeMembers

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


mapType : Type a -> Scala.Type
mapType tpe =
    case tpe of
        Type.Variable a name ->
            Scala.TypeVar (name |> Name.toTitleCase)

        Type.Reference a fQName argTypes ->
            let
                typeRef =
                    mapFQNameToTypeRef fQName
            in
            if List.isEmpty argTypes then
                typeRef

            else
                Scala.TypeApply typeRef (argTypes |> List.map mapType)

        Type.Tuple a elemTypes ->
            Scala.TupleType (elemTypes |> List.map mapType)

        Type.Record a fields ->
            Scala.TypeVar "Record"

        Type.ExtensibleRecord a argName fields ->
            Scala.TypeVar "ExtensibleRecord"

        Type.Function a argType returnType ->
            Scala.FunctionType (mapType argType) (mapType returnType)

        Type.Unit a ->
            Scala.TypeRef [ "scala" ] "Unit"


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

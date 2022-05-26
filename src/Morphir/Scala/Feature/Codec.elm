module Morphir.Scala.Feature.Codec exposing (..)

import Dict
import List
import List.Extra as ListExtra
import Maybe exposing (withDefault)
import Morphir.IR.AccessControlled exposing (Access(..), AccessControlled)
import Morphir.IR.Distribution exposing (Distribution)
import Morphir.IR.Documented exposing (Documented)
import Morphir.IR.FQName as FQName exposing (FQName)
import Morphir.IR.Module as Module exposing (ModuleName)
import Morphir.IR.Name as Name exposing (Name)
import Morphir.IR.Package as Package
import Morphir.IR.Path as Path exposing (Path)
import Morphir.IR.Type as Type exposing (Type(..))
import Morphir.SDK.ResultList as ResultList
import Morphir.Scala.AST as Scala exposing (Annotated)
import Morphir.Scala.Feature.Core as ScalaBackend exposing (mapFQNameToPathAndName, mapFQNameToTypeRef)
import Morphir.Scala.WellKnownTypes exposing (anyVal)
import Set exposing (Set)


type alias Options =
    { limitToModules : Maybe (Set ModuleName) }


type alias Error =
    String


mapModuleDefinitionToCodecs : Options -> Distribution -> Package.PackageName -> Path -> AccessControlled (Module.Definition ta (Type ())) -> List Scala.CompilationUnit
mapModuleDefinitionToCodecs opt distribution currentPackagePath currentModulePath accessControlledModuleDef =
    let
        newModulePath : String
        newModulePath =
            (List.head (List.reverse (Path.toList currentModulePath)) |> withDefault []) |> Name.toTitleCase

        scalaPackagePath : List String
        scalaPackagePath =
            currentPackagePath
                ++ currentModulePath
                |> List.map (Name.toCamelCase >> String.toLower)

        encoderTypeMembers : List (Scala.Annotated Scala.MemberDecl)
        encoderTypeMembers =
            accessControlledModuleDef.value.types
                |> Dict.toList
                |> List.concatMap
                    (\types ->
                        mapTypeDefinitionToEncoder currentPackagePath currentModulePath accessControlledModuleDef types
                            |> Result.withDefault []
                    )

        decoderTypeMembers : List (Scala.Annotated Scala.MemberDecl)
        decoderTypeMembers =
            accessControlledModuleDef.value.types
                |> Dict.toList
                |> List.concatMap
                    (\types ->
                        mapTypeDefinitionToDecoder currentPackagePath currentModulePath accessControlledModuleDef types
                            |> Result.withDefault []
                    )

        moduleUnit : Scala.CompilationUnit
        moduleUnit =
            { dirPath = scalaPackagePath
            , fileName = "Codec.scala"
            , packageDecl = scalaPackagePath
            , imports = []
            , typeDecls =
                [ Scala.Documented (Just (String.join "" [ "Generated based on ", currentModulePath |> Path.toString Name.toTitleCase "." ]))
                    (Scala.Annotated []
                        (Scala.Object
                            { modifiers =
                                case accessControlledModuleDef.access of
                                    Public ->
                                        []

                                    Private ->
                                        [ Scala.Private
                                            (currentPackagePath
                                                |> ListExtra.last
                                                |> Maybe.map (Name.toCamelCase >> String.toLower)
                                            )
                                        ]
                            , name =
                                "Codec"
                            , members =
                                List.concat [ encoderTypeMembers, decoderTypeMembers ]
                            , extends =
                                []
                            , body = Nothing
                            }
                        )
                    )
                ]
            }
    in
    [ moduleUnit ]


{-|

    Maps a Morphir Type Definition to an Encoder

-}
mapTypeDefinitionToEncoder : Package.PackageName -> Path -> AccessControlled (Module.Definition ta (Type ())) -> ( Name, AccessControlled (Documented (Type.Definition ta)) ) -> Result Error (List (Scala.Annotated Scala.MemberDecl))
mapTypeDefinitionToEncoder currentPackagePath currentModulePath accessControlledModuleDef ( typeName, accessControlledDocumentedTypeDef ) =
    case accessControlledDocumentedTypeDef.value.value of
        Type.TypeAliasDefinition typeParams typeExp ->
            let
                ( scalaTypePath, scalaName ) =
                    ScalaBackend.mapFQNameToPathAndName (FQName.fQName currentPackagePath currentModulePath typeName)
            in
            genEncodeReference typeExp
                |> Result.map
                    (\encodeValue ->
                        [ Scala.withoutAnnotation
                            (Scala.ValueDecl
                                { modifiers = [ Scala.Implicit ]
                                , pattern = Scala.NamedMatch ("encode" :: typeName |> Name.toCamelCase)
                                , valueType =
                                    Just
                                        (Scala.TypeApply
                                            (Scala.TypeRef [ "io", "circe" ] "Encoder")
                                            [ Scala.TypeRef scalaTypePath (scalaName |> Name.toTitleCase)
                                            ]
                                        )
                                , value =
                                    encodeValue |> Scala.Lambda [ ( "a", Just (Scala.TypeRef scalaTypePath (scalaName |> Name.toTitleCase)) ) ]
                                }
                            )
                        ]
                    )

        Type.CustomTypeDefinition typeParams accessControlledCtors ->
            Ok
                (mapCustomTypeDefinitionToEncoder
                    currentPackagePath
                    currentModulePath
                    accessControlledModuleDef.value
                    typeName
                    typeParams
                    accessControlledCtors
                )


mapCustomTypeDefinitionToEncoder : Package.PackageName -> Path -> Module.Definition ta (Type ()) -> Name -> List Name -> AccessControlled (Type.Constructors a) -> List (Scala.Annotated Scala.MemberDecl)
mapCustomTypeDefinitionToEncoder currentPackagePath currentModulePath moduleDef typeName typeParams accessControlledCtors =
    let
        ( scalaTypePath, scalaName ) =
            ScalaBackend.mapFQNameToPathAndName (FQName.fQName currentPackagePath currentModulePath typeName)

        sealedTraitHierarchy =
            [ Scala.Trait
                { modifiers = [ Scala.Sealed ]
                , name = "encode" ++ (typeName |> Name.toTitleCase)
                , typeArgs = typeParams |> List.map (Name.toTitleCase >> Scala.TypeVar)
                , extends = []
                , members = []
                }
            , Scala.Object
                { modifiers = []
                , name = typeName |> Name.toTitleCase
                , extends = []
                , members = []
                , body = Nothing
                }
            ]
    in
    case accessControlledCtors.value |> Dict.toList of
        [ ( ctorName, ctorArgs ) ] ->
            -- When the type name is the same as the constructor name
            if ctorName == typeName then
                if List.length ctorArgs == 1 then
                    [ Scala.withoutAnnotation
                        (Scala.ValueDecl
                            { modifiers = [ Scala.Implicit ]
                            , pattern = Scala.NamedMatch ("encode" :: ctorName |> Name.toCamelCase)
                            , valueType =
                                Just
                                    (Scala.TypeApply
                                        (Scala.TypeRef [ "io", "circe" ] "Encoder")
                                        [ Scala.TypeRef scalaTypePath (scalaName |> Name.toTitleCase)
                                        ]
                                    )
                            , value =
                                Scala.Lambda [ ( "a", Just (Scala.TypeRef scalaTypePath (scalaName |> Name.toTitleCase)) ) ]
                                    (Scala.Apply (Scala.Select (Scala.Ref [ "io", "circe" ] "Json") "arr")
                                        [ Scala.ArgValue Nothing (Scala.Select (Scala.Ref [ "io", "circe" ] "Json") "fromString")
                                        ]
                                    )
                            }
                        )
                    ]
                    -- If the length of the ctorArgs is 2 or more

                else
                    let
                        encoderArgs =
                            ctorArgs
                                |> List.map
                                    (\( argName, argType ) ->
                                        Scala.ArgValue Nothing
                                            (Scala.Apply (genEncodeReference argType |> Result.withDefault (Scala.Variable ""))
                                                [ Scala.ArgValue Nothing (Scala.Select (Scala.Variable "a") (argName |> Name.toCamelCase)) ]
                                            )
                                    )
                    in
                    [ Scala.withoutAnnotation
                        (Scala.ValueDecl
                            { modifiers = [ Scala.Implicit ]
                            , pattern = Scala.NamedMatch ("encode" :: scalaName |> Name.toCamelCase)
                            , valueType =
                                Just
                                    (Scala.TypeApply
                                        (Scala.TypeRef [ "io", "circe" ] "Encoder")
                                        [ Scala.TypeRef scalaTypePath (scalaName |> Name.toTitleCase)
                                        ]
                                    )
                            , value =
                                Scala.Lambda [ ( "a", Just (Scala.TypeRef scalaTypePath (scalaName |> Name.toTitleCase)) ) ]
                                    (Scala.Apply (Scala.Select (Scala.Ref [ "io", "circe" ] "Json") "arr") encoderArgs)
                            }
                        )
                    ]

            else
            -- When the  type name is not the same as the Constructor name
            if
                List.length ctorArgs == 1
            then
                [ Scala.withoutAnnotation
                    (Scala.ValueDecl
                        { modifiers = [ Scala.Implicit ]
                        , pattern = Scala.NamedMatch ("encode" :: ctorName |> Name.toCamelCase)
                        , valueType =
                            Just
                                (Scala.TypeApply
                                    (Scala.TypeRef [ "io", "circe" ] "Encoder")
                                    [ Scala.TypeRef scalaTypePath (scalaName |> Name.toTitleCase)
                                    ]
                                )
                        , value =
                            Scala.Lambda [ ( "a", Just (Scala.TypeRef scalaTypePath (scalaName |> Name.toTitleCase)) ) ]
                                (Scala.Apply (Scala.Select (Scala.Ref [ "io", "circe" ] "Json") "arr")
                                    [ Scala.ArgValue Nothing (Scala.Select (Scala.Ref [ "io", "circe" ] "Json") "fromString")
                                    ]
                                )
                        }
                    )
                ]
                -- If the length of the ctorArgs is 2 or more

            else
                let
                    encoderArgs =
                        ctorArgs
                            |> List.map
                                (\( argName, argType ) ->
                                    Scala.ArgValue Nothing
                                        (Scala.Apply (genEncodeReference argType |> Result.withDefault (Scala.Variable ""))
                                            [ Scala.ArgValue Nothing (Scala.Select (Scala.Variable "a") (argName |> Name.toCamelCase)) ]
                                        )
                                )
                in
                [ Scala.withoutAnnotation
                    (Scala.ValueDecl
                        { modifiers = [ Scala.Implicit ]
                        , pattern = Scala.NamedMatch ("encode" :: scalaName |> Name.toCamelCase)
                        , valueType =
                            Just
                                (Scala.TypeApply
                                    (Scala.TypeRef [ "io", "circe" ] "Encoder")
                                    [ Scala.TypeRef scalaTypePath (scalaName |> Name.toTitleCase)
                                    ]
                                )
                        , value =
                            Scala.Lambda [ ( "a", Just (Scala.TypeRef scalaTypePath (scalaName |> Name.toTitleCase)) ) ]
                                (Scala.Apply (Scala.Select (Scala.Ref [ "io", "circe" ] "Json") "arr") encoderArgs)
                        }
                    )
                ]

        _ ->
            List.concat
                []


mapCustomTypeDefinitionToDecoder : Package.PackageName -> Path -> Module.Definition ta (Type ()) -> Name -> List Name -> AccessControlled (Type.Constructors a) -> List (Scala.Annotated Scala.MemberDecl)
mapCustomTypeDefinitionToDecoder currentPackagePath currentModulePath moduleDef typeName typeParams accessControlledCtors =
    let
        ( scalaTypePath, scalaName ) =
            ScalaBackend.mapFQNameToPathAndName (FQName.fQName currentPackagePath currentModulePath typeName)

        caseClass name args extends =
            if List.isEmpty args then
                Scala.Object
                    { modifiers = [ Scala.Case ]
                    , name = "decode" :: name |> Name.toCamelCase
                    , extends = extends
                    , members = []
                    , body = Nothing
                    }

            else
                Scala.Class
                    { modifiers = [ Scala.Final, Scala.Case ]
                    , name = "decode" :: name |> Name.toCamelCase
                    , typeArgs = []
                    , ctorArgs =
                        args
                            |> List.map
                                (\( argName, argType ) ->
                                    { modifiers = []
                                    , tpe =
                                        Scala.TypeApply
                                            (Scala.TypeRef [ "io", "circe" ] "Decoder")
                                            [ Scala.TypeRef scalaTypePath (name |> Name.toTitleCase)
                                            ]
                                    , name = argName |> Name.toCamelCase
                                    , defaultValue = Nothing
                                    }
                                )
                            |> List.singleton
                    , extends = extends
                    , members = []
                    }

        parentTraitRef =
            mapFQNameToTypeRef ( currentPackagePath, currentModulePath, typeName )

        ( parentPackagePath, parentTraitName ) =
            let
                ( thePath, theName ) =
                    mapFQNameToPathAndName ( currentPackagePath, currentModulePath, typeName )
            in
            ( thePath, theName |> Name.toTitleCase )

        sealedTraitHierarchy =
            [ Scala.Trait
                { modifiers = [ Scala.Sealed ]
                , name = typeName |> Name.toTitleCase
                , typeArgs = typeParams |> List.map (Name.toTitleCase >> Scala.TypeVar)
                , extends = []
                , members = []
                }
            , Scala.Object
                { modifiers = []
                , name = typeName |> Name.toTitleCase
                , extends = []
                , members =
                    accessControlledCtors.value
                        |> Dict.toList
                        |> List.map
                            (\( ctorName, ctorArgs ) ->
                                Scala.withAnnotation []
                                    (caseClass
                                        ctorName
                                        ctorArgs
                                        (if List.isEmpty typeParams then
                                            [ parentTraitRef ]

                                         else
                                            [ Scala.TypeApply parentTraitRef (typeParams |> List.map (Name.toTitleCase >> Scala.TypeVar)) ]
                                        )
                                        |> Scala.MemberTypeDecl
                                    )
                            )
                , body = Nothing
                }
            ]
    in
    case accessControlledCtors.value |> Dict.toList of
        [ ( ctorName, ctorArgs ) ] ->
            if ctorName == typeName then
                if List.length ctorArgs == 1 then
                    [ Scala.withoutAnnotation
                        (Scala.MemberTypeDecl
                            (caseClass ctorName ctorArgs [ anyVal ])
                        )
                    ]

                else
                    [ Scala.withoutAnnotation
                        (Scala.MemberTypeDecl
                            (caseClass ctorName ctorArgs [])
                        )
                    ]

            else
                List.concat
                    [ sealedTraitHierarchy
                        |> List.map (Scala.MemberTypeDecl >> Scala.withoutAnnotation)
                    , []
                    ]

        _ ->
            List.concat
                [ sealedTraitHierarchy
                    |> List.map (Scala.MemberTypeDecl >> Scala.withoutAnnotation)
                , []
                ]


{-|

    Maps a Morphir Type Definition to a Decoder

-}
mapTypeDefinitionToDecoder : Package.PackageName -> Path -> AccessControlled (Module.Definition ta (Type ())) -> ( Name, AccessControlled (Documented (Type.Definition ta)) ) -> Result Error (List (Scala.Annotated Scala.MemberDecl))
mapTypeDefinitionToDecoder currentPackagePath currentModulePath accessControlledModuleDef ( typeName, accessControlledDocumentedTypeDef ) =
    case accessControlledDocumentedTypeDef.value.value of
        Type.TypeAliasDefinition typeArgs typeExp ->
            let
                ( scalaTypePath, scalaName ) =
                    ScalaBackend.mapFQNameToPathAndName (FQName.fQName currentPackagePath currentModulePath typeName)
            in
            genDecodeReference (FQName.fQName currentPackagePath currentModulePath typeName) typeExp
                |> Result.map
                    (\encodeValue ->
                        [ Scala.withoutAnnotation
                            (Scala.ValueDecl
                                { modifiers = [ Scala.Implicit ]
                                , pattern = Scala.NamedMatch ("decode" :: typeName |> Name.toCamelCase)
                                , valueType =
                                    Just
                                        (Scala.TypeApply
                                            (Scala.TypeRef [ "io", "circe" ] "Decoder")
                                            [ Scala.TypeRef scalaTypePath (scalaName |> Name.toTitleCase)
                                            ]
                                        )
                                , value =
                                    encodeValue |> Scala.Lambda [ ( "c", Just (Scala.TypeRef [ "io.circe" ] "HCursor") ) ]
                                }
                            )
                        ]
                    )

        Type.CustomTypeDefinition typeParams accessControlledCtors ->
            Ok
                (mapCustomTypeDefinitionToDecoder
                    currentPackagePath
                    currentModulePath
                    accessControlledModuleDef.value
                    typeName
                    typeParams
                    accessControlledCtors
                )


{-|

    Get an Encoder reference for a Type

-}
genEncodeReference : Type ta -> Result Error Scala.Value
genEncodeReference tpe =
    case tpe of
        Type.Variable _ varName ->
            Ok (Scala.Variable ("encode" :: varName |> Name.toCamelCase))

        Type.Reference _ ( packageName, moduleName, typeName ) typeArgs ->
            let
                scalaPackageName : List String
                scalaPackageName =
                    packageName ++ moduleName |> List.map (Name.toCamelCase >> String.toLower)

                scalaModuleName : String
                scalaModuleName =
                    "Codec"

                scalaReference : Scala.Value
                scalaReference =
                    Scala.Ref
                        scalaPackageName
                        ("encode" :: typeName |> Name.toCamelCase)
            in
            Ok scalaReference

        Type.Tuple a types ->
            Debug.todo "implement"

        Type.Record a fields ->
            let
                objFields : Result Error (List Scala.ArgValue)
                objFields =
                    fields
                        |> List.map
                            (\field ->
                                genEncodeReference field.tpe
                                    |> Result.map
                                        (\fieldValueEncoder ->
                                            let
                                                fieldNameLiteral : Scala.Value
                                                fieldNameLiteral =
                                                    Scala.Literal (Scala.StringLit (Name.toCamelCase field.name))

                                                fieldName : Scala.Name
                                                fieldName =
                                                    Name.toCamelCase field.name
                                            in
                                            Scala.ArgValue Nothing
                                                (Scala.Tuple
                                                    [ fieldNameLiteral
                                                    , Scala.Apply fieldValueEncoder [ Scala.ArgValue Nothing (Scala.Select (Scala.Variable "a") fieldName) ]
                                                    ]
                                                )
                                        )
                            )
                        |> ResultList.keepFirstError

                objRef : Result Error Scala.Value
                objRef =
                    objFields
                        |> Result.map (Scala.Apply (Scala.Ref [ "io", "circe", "Json" ] "obj"))
            in
            objRef

        Type.ExtensibleRecord a name fields ->
            Debug.todo "implement"

        Type.Function a argType returnType ->
            Err "Cannot encode a function"

        Type.Unit a ->
            Debug.todo "implement"


{-|

    Get an Decoder reference for a Type

-}
genDecodeReference : FQName -> Type ta -> Result Error Scala.Value
genDecodeReference fqName tpe =
    case tpe of
        Type.Variable _ varName ->
            Ok (Scala.Variable ("decode" :: varName |> Name.toCamelCase))

        Type.Reference _ ( packageName, moduleName, typeName ) typeArgs ->
            let
                scalaPackageName =
                    packageName ++ moduleName |> List.map (Name.toCamelCase >> String.toLower)

                scalaModuleName =
                    "Codec"

                scalaReference =
                    Scala.Ref
                        (scalaPackageName ++ [ scalaModuleName ])
                        ("decode" :: typeName |> Name.toCamelCase)
            in
            Ok scalaReference

        Type.Tuple a types ->
            Debug.todo "Add Implementation"

        Record a fields ->
            let
                generatorsResult : Result Error (List Scala.Generator)
                generatorsResult =
                    fields
                        |> List.map
                            (\field ->
                                genDecodeReference fqName field.tpe
                                    |> Result.map
                                        (\fieldValueDecoder ->
                                            let
                                                fieldNameLiteral : Scala.Value
                                                fieldNameLiteral =
                                                    Scala.Literal (Scala.StringLit (field.name |> Name.toCamelCase))

                                                downFieldApply : Scala.Value
                                                downFieldApply =
                                                    Scala.Apply (Scala.Select (Scala.Variable "c") "downField") [ Scala.ArgValue Nothing fieldNameLiteral ]

                                                downFieldApplyWithAs : Scala.Value
                                                downFieldApplyWithAs =
                                                    Scala.Select downFieldApply "as"

                                                forCompFieldRHS : Scala.Value
                                                forCompFieldRHS =
                                                    Scala.Apply downFieldApplyWithAs [ Scala.ArgValue Nothing fieldValueDecoder ]

                                                forCompField : Scala.Generator
                                                forCompField =
                                                    Scala.Extract (Scala.NamedMatch (field.name |> Name.toCamelCase)) forCompFieldRHS
                                            in
                                            forCompField
                                        )
                            )
                        |> ResultList.keepFirstError

                yieldValue : List Scala.ArgValue
                yieldValue =
                    fields
                        |> List.map
                            (\field ->
                                Scala.ArgValue Nothing (Scala.Variable (Name.toCamelCase field.name))
                            )

                ( path, scalaName ) =
                    mapFQNameToPathAndName fqName
            in
            generatorsResult
                |> Result.map
                    (\generators ->
                        Scala.ForComp generators (Scala.Apply (Scala.Ref path (scalaName |> Name.toCamelCase)) yieldValue)
                    )

        Function a argType returnType ->
            Err "Cannot decode a function"

        Type.Unit a ->
            Debug.todo "Implement"

        ExtensibleRecord a name fields ->
            Debug.todo "Implement"

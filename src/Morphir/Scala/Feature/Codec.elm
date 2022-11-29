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


type alias Error =
    String


circePackagePath : List String
circePackagePath =
    [ "io", "circe" ]


circePathString : String
circePathString =
    String.join "." circePackagePath


circeJsonPath : List String
circeJsonPath =
    List.concat [ circePackagePath, [ "Json" ] ]


circeJsonPathString : String
circeJsonPathString =
    String.join "." circeJsonPath



{-
   This is the entry point for the Codecs backend. This function takes Distribution and returns a list of compilation units.
   All the types defined in the distribution are converted into Codecs in the output language. It uses
   the two helper functions mapTypeDefinitionToEncoder and mapTypeDefinitionToDecoder
-}


mapModuleDefinitionToCodecs : Package.PackageName -> Path -> AccessControlled (Module.Definition ta (Type ())) -> List Scala.CompilationUnit
mapModuleDefinitionToCodecs currentPackagePath currentModulePath accessControlledModuleDef =
    let
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

    Maps a Morphir Type Definition to an Encoder. It takes an access controlled documented type definition and  returns a
    Result list of Scala.Annotated Member Declaration

-}
mapTypeDefinitionToEncoder : Package.PackageName -> Path -> AccessControlled (Module.Definition ta (Type ())) -> ( Name, AccessControlled (Documented (Type.Definition ta)) ) -> Result Error (List (Scala.Annotated Scala.MemberDecl))
mapTypeDefinitionToEncoder currentPackagePath currentModulePath accessControlledModuleDef ( typeName, accessControlledDocumentedTypeDef ) =
    case accessControlledDocumentedTypeDef.value.value of
        Type.TypeAliasDefinition _ typeExp ->
            let
                ( scalaTypePath, scalaName ) =
                    ScalaBackend.mapFQNameToPathAndName (FQName.fQName currentPackagePath currentModulePath typeName)
            in
            genEncodeReference scalaName typeExp
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
                                    encodeValue |> Scala.Lambda [ ( scalaName |> Name.toCamelCase, Just (Scala.TypeRef scalaTypePath (scalaName |> Name.toTitleCase)) ) ]
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



{-
   This function maps a custom type definition to a Scala encoder
-}


mapCustomTypeDefinitionToEncoder : Package.PackageName -> Path -> Module.Definition ta (Type ()) -> Name -> List Name -> AccessControlled (Type.Constructors a) -> List (Scala.Annotated Scala.MemberDecl)
mapCustomTypeDefinitionToEncoder currentPackagePath currentModulePath moduleDef typeName typeParams accessControlledCtors =
    let
        ( scalaTypePath, scalaName ) =
            ScalaBackend.mapFQNameToPathAndName (FQName.fQName currentPackagePath currentModulePath typeName)

        patternMatch =
            accessControlledCtors.value
                |> Dict.toList
                |> List.map
                    (\( ctorName, ctorArgs ) ->
                        composeEncoder ( currentPackagePath, currentModulePath, ctorName ) ctorArgs
                    )
    in
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
                Scala.Lambda [ ( scalaName |> Name.toCamelCase, Just (Scala.TypeRef scalaTypePath (scalaName |> Name.toTitleCase)) ) ]
                    (Scala.Match (Scala.Variable (scalaName |> Name.toCamelCase)) (Scala.MatchCases patternMatch))
            }
        )
    ]


composeEncoder : FQName -> List ( Name, Type ta ) -> ( Scala.Pattern, Scala.Value )
composeEncoder (( _, _, ctorName ) as fqName) ctorArgs =
    let
        scalaFqn =
            ScalaBackend.mapFQNameToPathAndName fqName
                |> Tuple.mapFirst (String.join ".")
                |> Tuple.mapSecond Name.toTitleCase
                |> (\( scalaTypePath, scalaName ) -> String.join "." [ scalaTypePath, scalaName ])

        args =
            ctorArgs
                |> List.map
                    (\( argName, argType ) ->
                        let
                            typeRef : Scala.Value
                            typeRef =
                                genEncodeReference [] argType |> Result.withDefault (Scala.Variable "")

                            arg =
                                Scala.Variable (argName |> Name.toCamelCase)
                        in
                        Scala.Apply typeRef [ Scala.ArgValue Nothing arg ]
                    )

        argNames =
            ctorArgs
                |> List.map
                    (\arg ->
                        Scala.NamedMatch (Tuple.first arg |> Name.toCamelCase)
                    )
    in
    if List.isEmpty ctorArgs then
        ( Scala.NamedMatch scalaFqn, Scala.Apply (Scala.Variable scalaFqn) [] )

    else
        ( Scala.UnapplyMatch [] scalaFqn argNames
        , Scala.Apply (Scala.Ref circeJsonPath "arr")
            ([ Scala.Apply (Scala.Ref circeJsonPath "fromString")
                (List.singleton <|
                    Scala.ArgValue Nothing <|
                        Scala.Literal <|
                            Scala.StringLit <|
                                Name.toTitleCase ctorName
                )
             ]
                ++ args
                |> List.map (Scala.ArgValue Nothing)
            )
        )


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
                    (\decodeValue ->
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
                                    decodeValue |> Scala.Lambda [ ( scalaName |> Name.toCamelCase, Just (Scala.TypeRef [ "io.circe" ] "HCursor") ) ]
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


mapCustomTypeDefinitionToDecoder : Package.PackageName -> Path -> Module.Definition ta (Type ()) -> Name -> List Name -> AccessControlled (Type.Constructors a) -> List (Scala.Annotated Scala.MemberDecl)
mapCustomTypeDefinitionToDecoder currentPackagePath currentModulePath moduleDef typeName typeParams accessControlledCtors =
    let
        ( scalaTypePath, scalaName ) =
            ScalaBackend.mapFQNameToPathAndName (FQName.fQName currentPackagePath currentModulePath typeName)

        argIndex =
            scalaName |> Name.toCamelCase

        downApply =
            argIndex ++ ".downN(0)" ++ ".as[io.circe.Json.String]" ++ ".flatMap"

        patternMatch : List ( Scala.Pattern, Scala.Value )
        patternMatch =
            accessControlledCtors.value
                |> Dict.toList
                |> List.map
                    (\( ctorName, ctorArgs ) ->
                        composeDecoder ( currentPackagePath, currentModulePath, ctorName ) ctorArgs scalaName
                    )
    in
    [ Scala.withoutAnnotation
        (Scala.ValueDecl
            { modifiers = [ Scala.Implicit ]
            , pattern = Scala.NamedMatch ("decode" :: typeName |> Name.toCamelCase)
            , valueType =
                Just
                    (Scala.TypeApply
                        (Scala.TypeRef [ "io", "circe" ] "Decoder")
                        [ Scala.TypeRef scalaTypePath (typeName |> Name.toTitleCase)
                        ]
                    )

            --(Scala.Apply
            --    (Scala.Match (Scala.Variable downApply) (Scala.MatchCases patternMatch))
            --    [ Scala.ArgValue Nothing (Scala.Variable downApply) ]
            --)
            , value =
                Scala.Lambda [ ( scalaName |> Name.toCamelCase, Just (Scala.TypeRef [ "io", "circe" ] "HCursor") ) ]
                    (Scala.Apply
                        (Scala.Variable downApply)
                        [ Scala.ArgValue Nothing (Scala.Lambda [ ( "tag", Nothing ) ] (Scala.Match (Scala.Variable "tag") (Scala.MatchCases patternMatch))) ]
                    )
            }
        )
    ]


composeDecoder : FQName -> List ( Name, Type ta ) -> Name -> ( Scala.Pattern, Scala.Value )
composeDecoder fqName ctorArgs name =
    let
        scalaFqn =
            ScalaBackend.mapFQNameToPathAndName fqName
                |> Tuple.mapFirst (String.join ".")
                |> Tuple.mapSecond Name.toTitleCase
                |> (\( scalaTypePath, scalaName ) -> String.join "." [ scalaTypePath, scalaName ])

        args =
            ctorArgs
                |> List.map
                    (\( argName, argType ) ->
                        let
                            typeRefResult =
                                genDecodeReference fqName argType

                            arg =
                                Scala.Variable (argName |> Name.toCamelCase)
                        in
                        case typeRefResult of
                            Ok typeRef ->
                                Scala.Apply typeRef [ Scala.ArgValue Nothing arg ]

                            Err err ->
                                Scala.Literal (Scala.StringLit "Unable to obtain reference")
                    )

        generators =
            ctorArgs
                |> List.map
                    (\arg ->
                        let
                            argIndex =
                                String.right 1 (Tuple.first arg |> Name.toCamelCase)

                            downApply =
                                Scala.Variable ((name |> Name.toCamelCase) ++ ".downN(" ++ argIndex ++ ")")

                            typeRefResult =
                                genDecodeReference fqName (Tuple.second arg)

                            asSelect : Scala.Value
                            asSelect =
                                Scala.Select downApply "as"

                            generatorRHS =
                                case typeRefResult of
                                    Ok typeRef ->
                                        Scala.Apply asSelect [ Scala.ArgValue Nothing typeRef ]

                                    Err _ ->
                                        Scala.Literal (Scala.StringLit "Unable to obtain reference")
                        in
                        Scala.Extract (Scala.NamedMatch (Tuple.first arg |> Name.toCamelCase)) generatorRHS
                    )

        yeildArgValues =
            ctorArgs
                |> List.map
                    (\( argName, argType ) ->
                        Scala.ArgValue Nothing (Scala.Variable (argName |> Name.toCamelCase))
                    )

        yeildExpression =
            Scala.Apply (Scala.Variable scalaFqn) yeildArgValues
    in
    if List.isEmpty ctorArgs then
        ( Scala.NamedMatch scalaFqn, Scala.Apply (Scala.Variable scalaFqn) [] )

    else
        ( Scala.LiteralMatch (Scala.StringLit (name |> Name.toTitleCase))
        , Scala.ForComp generators yeildExpression
        )


{-|

    Get an Encoder reference for a Type

-}
genEncodeReference : Name -> Type ta -> Result Error Scala.Value
genEncodeReference tpeName tpe =
    case tpe of
        Type.Variable _ varName ->
            Ok (Scala.Variable ("encode" :: varName |> Name.toCamelCase))

        Type.Reference _ (( packageName, moduleName, typeName ) as fqName) typeArgs ->
            let
                scalaPackageName : List String
                scalaPackageName =
                    packageName ++ moduleName |> List.map (Name.toCamelCase >> String.toLower)

                codecPath : List String
                codecPath =
                    List.concat [ scalaPackageName, [ "Codec" ] ]

                encoderName : String
                encoderName =
                    "encode" :: typeName |> Name.toCamelCase

                scalaReference : Scala.Value
                scalaReference =
                    Scala.Ref
                        codecPath
                        encoderName
            in
            case FQName.toString fqName of
                "Morphir.SDK:Basics:int" ->
                    Ok <|
                        Scala.Apply (Scala.Ref circeJsonPath "fromInt")
                            [ Scala.ArgValue Nothing <|
                                Scala.Variable <|
                                    Name.toCamelCase
                                        tpeName
                            ]

                "Morphir.SDK:Basics:float" ->
                    Ok <|
                        Scala.Apply (Scala.Ref circeJsonPath "fromFloat")
                            [ Scala.ArgValue Nothing <|
                                Scala.Variable <|
                                    Name.toCamelCase
                                        tpeName
                            ]

                "Morphir.SDK:Basics:bool" ->
                    Ok <|
                        Scala.Apply (Scala.Ref circeJsonPath "fromBool")
                            [ Scala.ArgValue Nothing <|
                                Scala.Variable <|
                                    Name.toCamelCase
                                        tpeName
                            ]

                "Morphir.SDK:String:string" ->
                    Ok <|
                        Scala.Apply (Scala.Ref circeJsonPath "fromString")
                            [ Scala.ArgValue Nothing <|
                                Scala.Variable <|
                                    Name.toCamelCase
                                        tpeName
                            ]

                _ ->
                    Ok
                        scalaReference

        Type.Tuple a types ->
            let
                encodedTypesResult =
                    types
                        |> List.map
                            (\currentType ->
                                genEncodeReference tpeName currentType
                            )
                        |> ResultList.keepFirstError
                        |> Result.map
                            (\x ->
                                x |> List.map (\y -> Scala.ArgValue Nothing y)
                            )
            in
            encodedTypesResult
                |> Result.map
                    (\argVal ->
                        Scala.Apply (Scala.Variable "io.circe.arr") argVal
                    )

        Type.Record a fields ->
            let
                objFields : Result Error (List Scala.ArgValue)
                objFields =
                    fields
                        |> List.map
                            (\field ->
                                genEncodeReference tpeName field.tpe
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
                                                    , Scala.Apply fieldValueEncoder [ Scala.ArgValue Nothing (Scala.Select (Scala.Variable (tpeName |> Name.toCamelCase)) fieldName) ]
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
            let
                objFields : Result Error (List Scala.ArgValue)
                objFields =
                    fields
                        |> List.map
                            (\field ->
                                genEncodeReference tpeName field.tpe
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
                                                    , Scala.Apply fieldValueEncoder [ Scala.ArgValue Nothing (Scala.Select (Scala.Variable (tpeName |> Name.toCamelCase)) fieldName) ]
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

        Type.Function a argType returnType ->
            Err "Cannot encode a function"

        Type.Unit a ->
            Ok Scala.Unit


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
            let
                decodedTypesResult =
                    types
                        |> List.map
                            (\currentType ->
                                genDecodeReference fqName currentType
                            )
                        |> ResultList.keepFirstError
                        |> Result.map
                            (\val ->
                                val |> List.map (\y -> Scala.ArgValue Nothing y)
                            )
            in
            decodedTypesResult
                |> Result.map
                    (\argVal ->
                        Scala.Apply (Scala.Variable "io.circe.arr") argVal
                    )

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
                                                    Scala.Apply (Scala.Select (Scala.Variable (scalaName |> Name.toCamelCase)) "downField") [ Scala.ArgValue Nothing fieldNameLiteral ]

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
            Ok Scala.Unit

        ExtensibleRecord a name fields ->
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
                                                    Scala.Apply (Scala.Select (Scala.Variable (scalaName |> Name.toCamelCase)) "downField") [ Scala.ArgValue Nothing fieldNameLiteral ]

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

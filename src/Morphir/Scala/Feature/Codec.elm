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
import Morphir.Scala.Common exposing (mapPathToScalaPath, mapValueName, prefixKeywords)
import Morphir.Scala.Feature.Core as ScalaBackend exposing (mapFQNameToPathAndName)


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


prefixScalaKeywordsInName : Name -> Name
prefixScalaKeywordsInName name =
    Name.toList name
        |> List.map prefixKeywords


prefixScalaKeywordsInPath : Path -> Path
prefixScalaKeywordsInPath path =
    Path.toList path
        |> List.map
            prefixScalaKeywordsInName


scalaType : List Name -> Name -> Scala.Path -> Scala.Type
scalaType typeParams tpeName scalaTypePath =
    case typeParams of
        [] ->
            Scala.TypeRef scalaTypePath (tpeName |> Name.toTitleCase)

        params ->
            params
                |> List.map (\paramName -> Name.toTitleCase paramName |> Scala.TypeVar)
                |> Scala.TypeApply (Scala.TypeRef scalaTypePath (tpeName |> Name.toTitleCase))



{-
   This is the entry point for the Codecs backend. This function takes Distribution and returns a list of compilation units.
   All the types defined in the distribution are converted into Codecs in the output language. It uses
   the two helper functions mapTypeDefinitionToEncoder and mapTypeDefinitionToDecoder
-}


mapModuleDefinitionToCodecs : Package.PackageName -> Path -> AccessControlled (Module.Definition ta (Type ())) -> List Scala.CompilationUnit
mapModuleDefinitionToCodecs currentPackagePath_ currentModulePath_ accessControlledModuleDef =
    let
        currentPackagePath : Path
        currentPackagePath =
            prefixScalaKeywordsInPath currentPackagePath_

        currentModulePath : Path
        currentModulePath =
            prefixScalaKeywordsInPath currentModulePath_

        scalaPackagePath : List String
        scalaPackagePath =
            currentPackagePath
                ++ currentModulePath
                |> List.map (Name.toCamelCase >> String.toLower)

        encoderTypeMembers : List (Scala.Annotated Scala.MemberDecl)
        encoderTypeMembers =
            accessControlledModuleDef.value.types
                |> Dict.toList
                |> List.filterMap
                    (\types ->
                        case mapTypeDefinitionToEncoder currentPackagePath currentModulePath types of
                            Ok memberDecl ->
                                Just memberDecl

                            Err error ->
                                -- TODO Do something with this error
                                Nothing
                    )

        decoderTypeMembers : List (Scala.Annotated Scala.MemberDecl)
        decoderTypeMembers =
            accessControlledModuleDef.value.types
                |> Dict.toList
                |> List.filterMap
                    (\types ->
                        case mapTypeDefinitionToDecoder currentPackagePath currentModulePath types of
                            Ok memberDecl ->
                                Just memberDecl

                            Err error ->
                                -- TODO Do something with this error
                                Nothing
                    )

        moduleUnit : Scala.CompilationUnit
        moduleUnit =
            { dirPath = scalaPackagePath
            , fileName = "Codec.scala"
            , packageDecl = scalaPackagePath
            , imports = []
            , typeDecls =
                [ Scala.Documented (Just (String.join "" [ "Generated based on ", currentModulePath_ |> Path.toString Name.toTitleCase "." ]))
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
mapTypeDefinitionToEncoder : Package.PackageName -> Path -> ( Name, AccessControlled (Documented (Type.Definition ta)) ) -> Result Error (Scala.Annotated Scala.MemberDecl)
mapTypeDefinitionToEncoder currentPackagePath currentModulePath ( typeName, accessControlledDocumentedTypeDef ) =
    let
        ( scalaTypePath, scalaTypeName ) =
            ScalaBackend.mapFQNameToPathAndName (FQName.fQName currentPackagePath currentModulePath (prefixScalaKeywordsInName typeName))

        scalaDeclaration : Scala.Type -> Scala.Value -> Scala.Annotated Scala.MemberDecl
        scalaDeclaration scalaTpe scalaValue =
            Scala.withoutAnnotation
                (Scala.ValueDecl
                    { modifiers = [ Scala.Implicit ]
                    , pattern = Scala.NamedMatch ("encode" :: typeName |> Name.toCamelCase)
                    , valueType =
                        Just
                            (Scala.TypeApply
                                (Scala.TypeRef circePackagePath "Encoder")
                                [ scalaTpe
                                ]
                            )
                    , value =
                        scalaValue
                    }
                )
    in
    case accessControlledDocumentedTypeDef.value.value of
        Type.TypeAliasDefinition typeParams typeExp ->
            case typeParams of
                [] ->
                    mapTypeToEncoderReference scalaTypeName scalaTypePath typeExp
                        |> Result.map (scalaDeclaration (scalaType typeParams scalaTypeName scalaTypePath))

                _ ->
                    let
                        p =
                            typeParams
                                |> List.map (\a -> ( "encode" :: a, Nothing ))
                    in
                    mapTypeToEncoderReference scalaTypeName scalaTypePath typeExp
                        |> Result.map (encoderLambda p)
                        |> Result.map (scalaDeclaration (scalaType typeParams scalaTypeName scalaTypePath))

        Type.CustomTypeDefinition typeParams accessControlledCtors ->
            let
                patternMatch : Result Error (List ( Scala.Pattern, Scala.Value ))
                patternMatch =
                    accessControlledCtors.value
                        |> Dict.toList
                        |> List.map
                            (\( ctorName, ctorArgs ) ->
                                mapConstructorsToEncoders scalaTypePath ( currentPackagePath, currentModulePath, ctorName ) ctorArgs
                            )
                        |> ResultList.keepFirstError
            in
            patternMatch
                |> Result.map Scala.MatchCases
                |> Result.map (Scala.Match (Scala.Variable (scalaTypeName |> Name.toCamelCase)))
                |> Result.map (encoderLambda [ ( scalaTypeName, typeRef scalaTypeName scalaTypePath |> Just ) ])
                |> Result.map (scalaDeclaration (scalaType typeParams scalaTypeName scalaTypePath))



{-
   This function maps a custom type definition to a Scala encoder
-}


mapConstructorsToEncoders : Scala.Path -> FQName -> List ( Name, Type ta ) -> Result Error ( Scala.Pattern, Scala.Value )
mapConstructorsToEncoders tpePath (( _, _, ctorName ) as fqName_) ctorArgs =
    let
        fqName =
            let
                ( pn, mn, ln ) =
                    fqName_
            in
            ( prefixScalaKeywordsInPath pn, prefixScalaKeywordsInPath mn, ln )

        scalaFqn =
            ScalaBackend.mapFQNameToPathAndName fqName
                |> Tuple.mapFirst (String.join ".")
                |> Tuple.mapSecond Name.toTitleCase
                |> (\( scalaTypePath, scalaName ) -> String.join "." [ scalaTypePath, scalaName ])

        argsEncodersResult : Result Error (List Scala.Value)
        argsEncodersResult =
            ctorArgs
                |> List.map
                    (\( argName, argType ) ->
                        let
                            arg =
                                Scala.Variable (argName |> Name.toCamelCase)
                        in
                        mapTypeToEncoderReference tpePath [] argType
                            |> Result.map (\typeEncoder -> Scala.Apply typeEncoder [ Scala.ArgValue Nothing arg ])
                    )
                |> ResultList.keepFirstError

        argNames =
            ctorArgs
                |> List.map
                    (\arg ->
                        Scala.NamedMatch (Tuple.first arg |> Name.toCamelCase)
                    )
    in
    if List.isEmpty ctorArgs then
        ( Scala.UnapplyMatch [] scalaFqn argNames
        , Scala.Apply (Scala.Ref circeJsonPath "fromString")
            (List.singleton <|
                Scala.ArgValue Nothing <|
                    Scala.Literal <|
                        Scala.StringLit <|
                            Name.toTitleCase ctorName
            )
        )
            |> Ok

    else
        argsEncodersResult
            |> Result.map
                (\argsEncoders ->
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
                            ++ argsEncoders
                            |> List.map (Scala.ArgValue Nothing)
                        )
                    )
                )


{-|

    Get an Encoder reference for a Type

-}
mapTypeToEncoderReference : Name -> Scala.Path -> Type ta -> Result Error Scala.Value
mapTypeToEncoderReference tpeName tpePath tpe =
    case tpe of
        Type.Variable _ varName ->
            Scala.Variable ("encode" :: varName |> Name.toCamelCase)
                |> Ok

        -- Assuming that the encoders for a reference have already been handled. We just have to return the encoder reference
        Type.Reference _ ( packageName, moduleName, typeName ) typeArgs ->
            let
                scalaPackageName : List String
                scalaPackageName =
                    prefixScalaKeywordsInPath packageName ++ prefixScalaKeywordsInPath moduleName |> List.map (Name.toCamelCase >> String.toLower)

                codecPath : List String
                codecPath =
                    List.concat [ scalaPackageName, [ "Codec" ] ]

                encoderName : String
                encoderName =
                    "encode" :: typeName |> Name.toCamelCase

                scalaReference : List String -> String -> Scala.Value
                scalaReference path name =
                    Scala.Ref path name
            in
            case typeArgs of
                [] ->
                    Ok <| scalaReference codecPath encoderName

                _ ->
                    typeArgs
                        |> List.map (\typeArg -> mapTypeToEncoderReference tpeName tpePath typeArg)
                        |> ResultList.keepFirstError
                        |> Result.map (List.map (Scala.ArgValue Nothing))
                        |> Result.map (Scala.Apply (scalaReference codecPath encoderName))

        Type.Tuple a types ->
            let
                tupleEncoderRef : Scala.Value
                tupleEncoderRef =
                    Scala.Ref [ "morphir", "sdk", "tuple", "Codec" ] "encodeTuple"

                encodedTypesResult =
                    types
                        |> List.map
                            (\currentType ->
                                mapTypeToEncoderReference tpeName tpePath currentType
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
                        Scala.Apply tupleEncoderRef argVal
                    )

        Type.Record a fields ->
            let
                objFields : Result Error (List Scala.ArgValue)
                objFields =
                    fields
                        |> List.map
                            (\field ->
                                mapTypeToEncoderReference tpeName tpePath field.tpe
                                    |> Result.map
                                        (\fieldEncoder ->
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
                                                    , Scala.Apply fieldEncoder
                                                        [ Scala.ArgValue Nothing (Scala.Select (Scala.Variable (tpeName |> Name.toCamelCase)) fieldName) ]
                                                    ]
                                                )
                                        )
                            )
                        |> ResultList.keepFirstError

                objRef : Result Error Scala.Value
                objRef =
                    objFields
                        |> Result.map (Scala.Apply (Scala.Ref circeJsonPath "obj"))
            in
            objRef
                |> Result.map (encoderLambda [ ( tpeName, typeRef tpeName tpePath |> Just ) ])

        Type.ExtensibleRecord a name fields ->
            let
                objFields : Result Error (List Scala.ArgValue)
                objFields =
                    fields
                        |> List.map
                            (\field ->
                                mapTypeToEncoderReference tpeName tpePath field.tpe
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
                        |> Result.map (Scala.Apply (Scala.Ref circeJsonPath "obj"))
            in
            objRef |> Result.map (encoderLambda [ ( tpeName, typeRef tpeName tpePath |> Just ) ])

        Type.Function a argType returnType ->
            Err "Cannot encode a function"

        Type.Unit a ->
            Scala.Apply (Scala.Ref circeJsonPath "arr") []
                |> Ok


typeRef : Name -> Scala.Path -> Scala.Type
typeRef name path =
    Scala.TypeRef path (name |> prefixScalaKeywordsInName |> Name.toTitleCase)


encoderLambda : List ( Name, Maybe Scala.Type ) -> Scala.Value -> Scala.Value
encoderLambda types body =
    Scala.Lambda
        (types
            |> List.map
                (\( argName, tpe ) ->
                    ( argName
                        |> Name.toCamelCase
                    , tpe
                    )
                )
        )
        body


{-|

    Maps a Morphir Type Definition to a Decoder

-}
mapTypeDefinitionToDecoder : Package.PackageName -> Path -> ( Name, AccessControlled (Documented (Type.Definition ta)) ) -> Result Error (Scala.Annotated Scala.MemberDecl)
mapTypeDefinitionToDecoder currentPackagePath currentModulePath ( typeName, accessControlledDocumentedTypeDef ) =
    let
        hCursor =
            "c"

        ( scalaTypePath, scalaTypeName ) =
            ScalaBackend.mapFQNameToPathAndName (FQName.fQName currentPackagePath currentModulePath typeName)

        scalaDeclaration : Scala.Type -> Scala.Value -> Scala.Annotated Scala.MemberDecl
        scalaDeclaration scalaTpe scalaValue =
            Scala.withoutAnnotation
                (Scala.ValueDecl
                    { modifiers = [ Scala.Implicit ]
                    , pattern = Scala.NamedMatch ("decode" :: typeName |> Name.toCamelCase)
                    , valueType =
                        Just
                            (Scala.TypeApply
                                (Scala.TypeRef [ "io", "circe" ] "Decoder")
                                [ scalaTpe
                                ]
                            )
                    , value =
                        scalaValue
                    }
                )
    in
    case accessControlledDocumentedTypeDef.value.value of
        Type.TypeAliasDefinition typeArgs typeExp ->
            case typeArgs of
                [] ->
                    mapTypeToDecoderReference scalaTypeName circePackagePath typeExp
                        |> Result.map (scalaDeclaration (scalaType typeArgs scalaTypeName scalaTypePath))

                _ ->
                    let
                        p =
                            typeArgs
                                |> List.map (\a -> ( "decode" :: a, Nothing ))
                    in
                    mapTypeToDecoderReference scalaTypeName circePackagePath typeExp
                        |> Result.map (decoderLambda p)
                        |> Result.map (scalaDeclaration (scalaType typeArgs scalaTypeName scalaTypePath))

        Type.CustomTypeDefinition typeParams accessControlledCtors ->
            let
                patternMatchResult : Result Error (List ( Scala.Pattern, Scala.Value ))
                patternMatchResult =
                    accessControlledCtors.value
                        |> Dict.toList
                        |> List.map
                            (\( ctorName, ctorArgs ) ->
                                mapConstructorsToDecoder ( currentPackagePath, currentModulePath, ctorName ) ctorArgs scalaTypeName
                            )
                        |> ResultList.keepFirstError

                downApply =
                    hCursor ++ ".downN(0)" ++ ".as[String]" ++ ".flatMap"

                scalaValueResult : Result Error Scala.Value
                scalaValueResult =
                    patternMatchResult
                        |> Result.map
                            (\patternMatch ->
                                Scala.Lambda [ ( "c", Just (Scala.TypeRef circePackagePath "HCursor") ) ]
                                    (Scala.Apply
                                        (Scala.Variable downApply)
                                        [ Scala.ArgValue Nothing (Scala.Lambda [ ( "tag", Nothing ) ] (Scala.Match (Scala.Variable "tag") (Scala.MatchCases patternMatch))) ]
                                    )
                            )
            in
            Result.map (\scalaValue -> scalaDeclaration (scalaType typeParams scalaTypeName scalaTypePath) scalaValue) scalaValueResult


mapConstructorsToDecoder : FQName -> List ( Name, Type ta ) -> Name -> Result Error ( Scala.Pattern, Scala.Value )
mapConstructorsToDecoder (( _, _, ctorName ) as fqName_) ctorArgs name =
    let
        fqName =
            let
                ( pn, mn, ln ) =
                    fqName_
            in
            ( prefixScalaKeywordsInPath pn, prefixScalaKeywordsInPath mn, ln )

        ( tpePath, tpeName ) =
            ScalaBackend.mapFQNameToPathAndName fqName

        scalaFqn =
            ScalaBackend.mapFQNameToPathAndName fqName
                |> Tuple.mapFirst (String.join ".")
                |> Tuple.mapSecond Name.toTitleCase
                |> (\( scalaTypePath, scalaName ) -> String.join "." [ scalaTypePath, scalaName ])

        generatorsResult : Result Error (List Scala.Generator)
        generatorsResult =
            ctorArgs
                |> List.map
                    (\arg ->
                        let
                            argIndex =
                                String.right 1 (Tuple.first arg |> Name.toCamelCase)

                            downApply =
                                Scala.Variable ("c" ++ ".downN(" ++ argIndex ++ ")")

                            asSelect : Scala.Value
                            asSelect =
                                Scala.Select downApply "as"

                            generatorRHS : Result Error Scala.Value
                            generatorRHS =
                                mapTypeToDecoderReference name tpePath (Tuple.second arg)
                                    |> Result.map (Scala.Apply asSelect << List.singleton << Scala.ArgValue Nothing)
                        in
                        generatorRHS
                            |> Result.map
                                (Scala.Extract (Scala.NamedMatch (Tuple.first arg |> Name.toCamelCase)))
                    )
                |> ResultList.keepFirstError

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
        --Scala.Apply (Scala.Variable scalaFqn) []
        ( Scala.LiteralMatch (Scala.StringLit (ctorName |> Name.toTitleCase))
        , Scala.Apply (Scala.Variable "Right")
            [ Scala.ArgValue Nothing <| Scala.Variable scalaFqn
            ]
        )
            |> Ok

    else
        generatorsResult
            |> Result.map
                (\generators ->
                    ( Scala.LiteralMatch (Scala.StringLit (ctorName |> Name.toTitleCase))
                    , Scala.ForComp generators yeildExpression
                    )
                )


{-|

    Get an Decoder reference for a Type

-}
mapTypeToDecoderReference : Name -> Scala.Path -> Type ta -> Result Error Scala.Value
mapTypeToDecoderReference tpeName tpePath tpe =
    case tpe of
        Type.Variable _ varName ->
            Scala.Variable ("decode" :: varName |> Name.toCamelCase)
                |> Ok

        Type.Reference _ ( packageName, moduleName, typeName ) typeArgs ->
            let
                scalaPackageName =
                    prefixScalaKeywordsInPath packageName
                        ++ prefixScalaKeywordsInPath moduleName
                        |> List.map (Name.toCamelCase >> String.toLower)

                codecPath : List String
                codecPath =
                    List.concat [ scalaPackageName, [ "Codec" ] ]

                decoderName : String
                decoderName =
                    "decode" :: typeName |> Name.toCamelCase

                scalaReference : List String -> String -> Scala.Value
                scalaReference path name =
                    Scala.Ref path name
            in
            case typeArgs of
                [] ->
                    Ok (scalaReference codecPath decoderName)

                _ ->
                    typeArgs
                        |> List.map (\typeArg -> mapTypeToDecoderReference tpeName tpePath typeArg)
                        |> ResultList.keepFirstError
                        |> Result.map (List.map (Scala.ArgValue Nothing))
                        |> Result.map (Scala.Apply (scalaReference codecPath decoderName))

        Type.Tuple a types ->
            let
                tupleDecoderRef : Scala.Value
                tupleDecoderRef =
                    Scala.Ref [ "morphir", "sdk", "tuple", "Codec" ] "decodeTuple"

                decodedTypesResult =
                    types
                        |> List.map
                            (\currentType ->
                                mapTypeToDecoderReference tpeName tpePath currentType
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
                        Scala.Apply tupleDecoderRef argVal
                    )

        Record a fields ->
            let
                generatorsResult : Result Error (List Scala.Generator)
                generatorsResult =
                    fields
                        |> List.map
                            (\field ->
                                mapTypeToDecoderReference tpeName tpePath field.tpe
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
            in
            generatorsResult
                |> Result.map
                    (\generators ->
                        Scala.ForComp generators (Scala.Apply (Scala.Ref tpePath (tpeName |> Name.toTitleCase)) yieldValue)
                            |> decoderLambda [ ( Name.fromString "c", typeRef (Name.fromString "c") circePackagePath |> Just ) ]
                    )

        Function a argType returnType ->
            Err "Cannot decode a function"

        Type.Unit a ->
            Scala.Unit
                |> Ok

        ExtensibleRecord a name fields ->
            let
                generatorsResult : Result Error (List Scala.Generator)
                generatorsResult =
                    fields
                        |> List.map
                            (\field ->
                                mapTypeToDecoderReference name tpePath field.tpe
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
            in
            generatorsResult
                |> Result.map
                    (\generators ->
                        Scala.ForComp generators (Scala.Apply (Scala.Ref tpePath (tpeName |> Name.toCamelCase)) yieldValue)
                            |> decoderLambda [ ( Name.fromString "c", typeRef (Name.fromString "c") circePackagePath |> Just ) ]
                    )


decoderLambda : List ( Name, Maybe Scala.Type ) -> Scala.Value -> Scala.Value
decoderLambda args body =
    Scala.Lambda
        (args |> List.map (Tuple.mapFirst Name.toCamelCase))
        body

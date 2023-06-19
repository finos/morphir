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
import Morphir.Scala.Common exposing (prefixKeywords)
import Morphir.Scala.Feature.Core as ScalaBackend exposing (mapFQNameToPathAndName)


type alias Error =
    String


type alias Errors =
    List String


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


scalaType : List Name -> Name -> Scala.Path -> Scala.Type
scalaType typeParams tpeName scalaTypePath =
    case typeParams of
        [] ->
            Scala.TypeRef scalaTypePath (tpeName |> Name.toTitleCase)

        params ->
            params
                |> List.map (\paramName -> Name.toTitleCase paramName |> Scala.TypeVar)
                |> Scala.TypeApply (Scala.TypeRef scalaTypePath (tpeName |> Name.toTitleCase))


typeRef : Name -> Scala.Path -> List Name -> Scala.Type
typeRef name path typeParams =
    case typeParams of
        [] ->
            Scala.TypeRef path (name |> Name.toTitleCase)

        _ ->
            typeParams
                |> List.map (Name.toTitleCase >> Scala.TypeVar)
                |> Scala.TypeApply
                    (Scala.TypeRef path (name |> Name.toTitleCase))


scalaDeclaration : String -> String -> Scala.Type -> Name -> List Name -> Scala.Value -> Scala.Annotated Scala.MemberDecl
scalaDeclaration codecPrefix codecType scalaTpe typeName typeParams scalaValue =
    case typeParams of
        [] ->
            Scala.withoutAnnotation
                (Scala.ValueDecl
                    { modifiers = [ Scala.Implicit ]
                    , pattern = Scala.NamedMatch (codecPrefix :: typeName |> Name.toCamelCase)
                    , valueType =
                        Just
                            (Scala.TypeApply
                                (Scala.TypeRef circePackagePath codecType)
                                [ scalaTpe
                                ]
                            )
                    , value =
                        scalaValue
                    }
                )

        _ ->
            let
                functionTypeArgs : List Scala.Type
                functionTypeArgs =
                    typeParams
                        |> List.map (Name.toTitleCase >> Scala.TypeVar)

                functionArgList : List Scala.ArgDecl
                functionArgList =
                    typeParams
                        |> List.map
                            (\typeArgName ->
                                { modifiers = []
                                , tpe =
                                    Scala.TypeApply
                                        (Scala.TypeRef circePackagePath codecType)
                                        [ Name.toTitleCase typeArgName |> Scala.TypeVar
                                        ]
                                , name = codecPrefix :: typeArgName |> Name.toCamelCase
                                , defaultValue = Nothing
                                }
                            )
            in
            Scala.withoutAnnotation
                (Scala.FunctionDecl
                    { modifiers = [ Scala.Implicit ]
                    , name = codecPrefix :: typeName |> Name.toCamelCase
                    , typeArgs = functionTypeArgs
                    , args = [ functionArgList ]
                    , returnType =
                        Just
                            (Scala.TypeApply
                                (Scala.TypeRef circePackagePath codecType)
                                [ scalaTpe
                                ]
                            )
                    , body =
                        Just scalaValue
                    }
                )


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



{-
   This is the entry point for the Codecs backend. This function takes Distribution and returns a list of compilation units.
   All the types defined in the distribution are converted into Codecs in the output language. It uses
   the two helper functions mapTypeDefinitionToEncoder and mapTypeDefinitionToDecoder
-}


mapModuleDefinitionToCodecs : Package.PackageName -> Path -> AccessControlled (Module.Definition ta (Type ())) -> Result Error (List Scala.CompilationUnit)
mapModuleDefinitionToCodecs currentPackagePath currentModulePath accessControlledModuleDef =
    let
        scalaPackagePath : List String
        scalaPackagePath =
            currentPackagePath
                ++ currentModulePath
                |> List.map (Name.toCamelCase >> String.toLower)

        encoderTypeMembersResult : Result Error (List (Scala.Annotated Scala.MemberDecl))
        encoderTypeMembersResult =
            accessControlledModuleDef.value.types
                |> Dict.toList
                |> List.map
                    (\types ->
                        mapTypeDefinitionToEncoder currentPackagePath currentModulePath types
                    )
                |> ResultList.keepFirstError

        decoderTypeMembersResult : Result Error (List (Scala.Annotated Scala.MemberDecl))
        decoderTypeMembersResult =
            accessControlledModuleDef.value.types
                |> Dict.toList
                |> List.map
                    (\types ->
                        mapTypeDefinitionToDecoder currentPackagePath currentModulePath types
                    )
                |> ResultList.keepFirstError

        moduleUnit : Result Error Scala.CompilationUnit
        moduleUnit =
            Result.map2
                (\encoderTypeMembers decoderTypeMembers ->
                    { dirPath = prefixKeywords scalaPackagePath
                    , fileName = "Codec.scala"
                    , packageDecl = scalaPackagePath
                    , imports = []
                    , typeDecls =
                        [ Scala.Documented (Just (String.join "" [ "Generated based on ", currentModulePath |> Path.toString Name.toTitleCase "." ]))
                            (Scala.withoutAnnotation
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
                )
                encoderTypeMembersResult
                decoderTypeMembersResult
    in
    Result.map List.singleton moduleUnit


{-|

    Maps a Morphir Type Definition to an Encoder. It takes an access controlled documented type definition and  returns a
    Result list of Scala.Annotated Member Declaration

-}
mapTypeDefinitionToEncoder : Package.PackageName -> Path -> ( Name, AccessControlled (Documented (Type.Definition ta)) ) -> Result Error (Scala.Annotated Scala.MemberDecl)
mapTypeDefinitionToEncoder currentPackagePath currentModulePath ( typeName, accessControlledDocumentedTypeDef ) =
    let
        typeFqn =
            FQName.fQName currentPackagePath currentModulePath typeName

        ( scalaTypePath, scalaTypeName ) =
            ScalaBackend.mapFQNameToPathAndName typeFqn
    in
    case accessControlledDocumentedTypeDef.value.value of
        Type.TypeAliasDefinition typeParams typeExp ->
            mapTypeToEncoderReference (Just typeFqn) typeName scalaTypePath typeParams typeExp
                |> Result.map (scalaDeclaration "encode" "Encoder" (scalaType typeParams scalaTypeName scalaTypePath) scalaTypeName typeParams)

        Type.CustomTypeDefinition typeParams accessControlledCtors ->
            let
                patternMatch : Result Error (List ( Scala.Pattern, Scala.Value ))
                patternMatch =
                    accessControlledCtors.value
                        |> Dict.toList
                        |> List.map
                            (\( ctorName, ctorArgs ) ->
                                mapConstructorsToEncoders scalaTypePath ( currentPackagePath, currentModulePath, ctorName ) ctorArgs typeParams
                            )
                        |> ResultList.keepFirstError
            in
            patternMatch
                |> Result.map Scala.MatchCases
                |> Result.map (Scala.Match (Scala.Variable (scalaTypeName |> Name.toCamelCase)))
                |> Result.map (encoderLambda [ ( scalaTypeName, typeRef scalaTypeName scalaTypePath typeParams |> Just ) ])
                |> Result.map (scalaDeclaration "encode" "Encoder" (scalaType typeParams scalaTypeName scalaTypePath) scalaTypeName typeParams)



{-
   This function maps a custom type definition to a Scala encoder
-}


mapConstructorsToEncoders : Scala.Path -> FQName -> List ( Name, Type ta ) -> List Name -> Result Error ( Scala.Pattern, Scala.Value )
mapConstructorsToEncoders tpePath (( _, _, ctorName ) as fqName) ctorArgs typeParams =
    let
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
                        mapTypeToEncoderReference Nothing argName [] typeParams argType
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
mapTypeToEncoderReference : Maybe FQName -> Name -> Scala.Path -> List Name -> Type ta -> Result Error Scala.Value
mapTypeToEncoderReference maybeFqn tpeName tpePath typeParams tpe =
    case tpe of
        Type.Variable _ varName ->
            Scala.Variable ("encode" :: varName |> Name.toCamelCase)
                |> Ok

        -- Assuming that the encoders for a reference have already been handled. We just have to return the encoder reference
        Type.Reference _ ( packageName, moduleName, typeName ) typeArgs ->
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
                    Scala.Ref codecPath encoderName
            in
            case typeArgs of
                [] ->
                    Ok <| scalaReference

                _ ->
                    typeArgs
                        |> List.map (\typeArg -> mapTypeToEncoderReference maybeFqn tpeName tpePath typeParams typeArg)
                        |> ResultList.keepFirstError
                        |> Result.map (List.map (Scala.ArgValue Nothing))
                        |> Result.map (Scala.Apply scalaReference)

        Type.Tuple a types ->
            let
                encodedTypesResult =
                    types
                        |> List.map
                            (\currentType ->
                                mapTypeToEncoderReference maybeFqn tpeName tpePath typeParams currentType
                            )
                        |> ResultList.keepFirstError
                        |> Result.map
                            (\elementsEncoderReference ->
                                elementsEncoderReference
                                    |> List.indexedMap
                                        (\index elEncodeRef ->
                                            Scala.Apply elEncodeRef
                                                [ Scala.ArgValue Nothing
                                                    (Scala.Select (Scala.Variable (Name.toCamelCase tpeName))
                                                        ("_" ++ String.fromInt (index + 1))
                                                    )
                                                ]
                                        )
                            )
            in
            encodedTypesResult
                |> Result.map
                    (\encodedElements ->
                        Scala.Lambda [ ( Name.toCamelCase tpeName, Just (ScalaBackend.mapType tpe) ) ]
                            (Scala.Apply (Scala.Ref circeJsonPath "arr")
                                (encodedElements |> List.map (Scala.ArgValue Nothing))
                            )
                    )

        Type.Record a fields ->
            let
                objFields : Result Error (List Scala.ArgValue)
                objFields =
                    fields
                        |> List.map
                            (\field ->
                                mapTypeToEncoderReference maybeFqn tpeName tpePath typeParams field.tpe
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

                recordTpe =
                    case maybeFqn of
                        Just fqn ->
                            typeParams
                                |> List.map (Variable a)
                                |> Type.Reference a fqn

                        Nothing ->
                            tpe
            in
            objRef
                |> Result.map (encoderLambda [ ( tpeName, ScalaBackend.mapType recordTpe |> Just ) ])

        Type.ExtensibleRecord a name fields ->
            let
                objFields : Result Error (List Scala.ArgValue)
                objFields =
                    fields
                        |> List.map
                            (\field ->
                                mapTypeToEncoderReference maybeFqn tpeName tpePath typeParams field.tpe
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
            objRef |> Result.map (encoderLambda [ ( tpeName, ScalaBackend.mapType tpe |> Just ) ])

        Type.Function a argType returnType ->
            Err "Cannot encode a function"

        Type.Unit a ->
            Scala.Ref [ "morphir", "sdk", "basics", "Codec" ] "encodeUnit"
                |> Ok


decoderLambda : List ( Name, Maybe Scala.Type ) -> Scala.Value -> Scala.Value
decoderLambda args body =
    Scala.Lambda
        (args |> List.map (Tuple.mapFirst Name.toCamelCase))
        body


{-|

    Maps a Morphir Type Definition to a Decoder, for Custom types we have to handle them specially , this is
    because Custom types with constructors can have 0 or more arguments.

    Example :

    type CustomType =
        CustomOne String
        CustomTwo Int
        CustomThree

In the example above, when the type CustomType is being decoded , the constructor CustomOne and its value are represented
in an array. Same applies to CustomTwo. We can then use the downN method from the HCursor class to move to elements in
the JSON array.
CustomThree is represented as a string and should be handled differently. To handle this use case we make use of the withFocus
method in the HCursor class. This allows us to modify the currently focused Json value with a function.
A function can then be used to convert the string to a Json Array which can then be decoded like other constructors

-}
mapTypeDefinitionToDecoder : Package.PackageName -> Path -> ( Name, AccessControlled (Documented (Type.Definition ta)) ) -> Result Error (Scala.Annotated Scala.MemberDecl)
mapTypeDefinitionToDecoder currentPackagePath currentModulePath ( typeName, accessControlledDocumentedTypeDef ) =
    let
        ( scalaTypePath, scalaTypeName ) =
            ScalaBackend.mapFQNameToPathAndName (FQName.fQName currentPackagePath currentModulePath typeName)
    in
    case accessControlledDocumentedTypeDef.value.value of
        Type.TypeAliasDefinition typeParams typeExp ->
            mapTypeToDecoderReference (Just ( scalaTypeName, scalaTypePath )) typeExp
                |> Result.map (scalaDeclaration "decode" "Decoder" (scalaType typeParams scalaTypeName scalaTypePath) scalaTypeName typeParams)

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

                hCursor =
                    Scala.Variable "c"

                underscore =
                    Scala.Variable "_"

                wrapSingleConstructorsWithArray =
                    Scala.Apply (Scala.Select hCursor "withFocus")
                        [ Scala.ArgValue Nothing
                            (Scala.Apply (Scala.Select underscore "withString")
                                [ Scala.ArgValue Nothing
                                    (Scala.Lambda [ ( "str", Nothing ) ]
                                        (Scala.Apply (Scala.Ref circeJsonPath "arr")
                                            [ Scala.ArgValue Nothing
                                                (Scala.Apply (Scala.Ref circeJsonPath "fromString")
                                                    [ Scala.ArgValue Nothing
                                                        (Scala.Variable "str")
                                                    ]
                                                )
                                            ]
                                        )
                                    )
                                ]
                            )
                        ]

                downApply : Scala.Value
                downApply =
                    Scala.Select
                        (circeAs (downN wrapSingleConstructorsWithArray 0)
                            (Scala.Ref [ "morphir", "sdk", "string", "Codec" ] "decodeString")
                        )
                        "flatMap"

                scalaValueResult : Result Error Scala.Value
                scalaValueResult =
                    patternMatchResult
                        |> Result.map
                            (\patternMatch ->
                                Scala.Lambda [ ( "c", Just (Scala.TypeRef circePackagePath "HCursor") ) ]
                                    (Scala.Apply
                                        downApply
                                        [ Scala.ArgValue Nothing
                                            (Scala.Lambda [ ( "tag", Nothing ) ]
                                                (Scala.Match (Scala.Variable "tag") (Scala.MatchCases patternMatch))
                                            )
                                        ]
                                    )
                            )
            in
            Result.map (scalaDeclaration "decode" "Decoder" (scalaType typeParams scalaTypeName scalaTypePath) scalaTypeName typeParams) scalaValueResult


mapConstructorsToDecoder : FQName -> List ( Name, Type ta ) -> Name -> Result Error ( Scala.Pattern, Scala.Value )
mapConstructorsToDecoder (( _, _, ctorName ) as fqName_) ctorArgs name =
    let
        fqName =
            let
                ( packageName, moduleName, localName ) =
                    fqName_
            in
            ( packageName, moduleName, localName )

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
                |> List.indexedMap
                    (\index arg ->
                        let
                            downApply =
                                downN c (index + 1)

                            generatorRHS : Result Error Scala.Value
                            generatorRHS =
                                mapTypeToDecoderReference Nothing (Tuple.second arg)
                                    |> Result.map (circeAs downApply)
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
        ( Scala.LiteralMatch (Scala.StringLit (ctorName |> Name.toTitleCase))
        , Scala.Apply (Scala.Ref [ "scala" ] "Right")
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
mapTypeToDecoderReference : Maybe ( Name, Scala.Path ) -> Type ta -> Result Error Scala.Value
mapTypeToDecoderReference maybeTypeNameAndPath tpe =
    case tpe of
        Type.Variable _ varName ->
            Scala.Variable ("decode" :: varName |> Name.toCamelCase)
                |> Ok

        Type.Reference _ ( packageName, moduleName, typeName ) typeArgs ->
            let
                scalaPackageName =
                    packageName
                        ++ moduleName
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
                        |> List.map (\typeArg -> mapTypeToDecoderReference maybeTypeNameAndPath typeArg)
                        |> ResultList.keepFirstError
                        |> Result.map (List.map (Scala.ArgValue Nothing))
                        |> Result.map (Scala.Apply (scalaReference codecPath decoderName))

        Type.Tuple a types ->
            let
                typeDecodersResult : Result Error (List Scala.Value)
                typeDecodersResult =
                    types
                        |> List.map
                            (\currentType ->
                                mapTypeToDecoderReference maybeTypeNameAndPath currentType
                            )
                        |> ResultList.keepFirstError

                generatorsResult : Result Error (List Scala.Generator)
                generatorsResult =
                    typeDecodersResult
                        |> Result.map
                            (\typeDecoders ->
                                typeDecoders
                                    |> List.indexedMap
                                        (\index typeDecoderRef ->
                                            Scala.Extract
                                                (Scala.NamedMatch
                                                    ("arg" ++ String.fromInt (index + 1))
                                                )
                                                (circeAs (downN c index)
                                                    typeDecoderRef
                                                )
                                        )
                            )

                yieldValue : Scala.Value
                yieldValue =
                    Scala.Tuple
                        (types
                            |> List.indexedMap
                                (\index _ ->
                                    Scala.Variable ("arg" ++ String.fromInt (index + 1))
                                )
                        )

                forCompResult : Result Error Scala.Value
                forCompResult =
                    generatorsResult
                        |> Result.map
                            (\generators ->
                                Scala.ForComp generators yieldValue
                            )
            in
            forCompResult
                |> Result.map
                    (\forComp ->
                        Scala.Lambda [ ( "c", Just (Scala.TypeRef circePackagePath "HCursor") ) ] forComp
                    )

        Record a fields ->
            let
                generatorsResult : Result Error (List Scala.Generator)
                generatorsResult =
                    fields
                        |> List.map
                            (\field ->
                                mapTypeToDecoderReference Nothing field.tpe
                                    |> Result.map
                                        (\fieldValueDecoder ->
                                            let
                                                downFieldApply : Scala.Value
                                                downFieldApply =
                                                    downField c (field.name |> Name.toCamelCase)

                                                forCompFieldRHS : Scala.Value
                                                forCompFieldRHS =
                                                    circeAs downFieldApply fieldValueDecoder

                                                forCompField : Scala.Generator
                                                forCompField =
                                                    Scala.Extract (Scala.NamedMatch (Name.toCamelCase field.name ++ "_")) forCompFieldRHS
                                            in
                                            forCompField
                                        )
                            )
                        |> ResultList.keepFirstError

                yieldArgs : List Scala.ArgValue
                yieldArgs =
                    fields
                        |> List.map
                            (\field ->
                                Scala.ArgValue Nothing (Scala.Variable (Name.toCamelCase field.name ++ "_"))
                            )

                yieldValue : Scala.Value
                yieldValue =
                    maybeTypeNameAndPath
                        |> Maybe.map (\( name, path ) -> Scala.Apply (Scala.Ref path (name |> Name.toTitleCase)) yieldArgs)
                        |> Maybe.withDefault
                            (Scala.StructuralValue
                                (fields
                                    |> List.map
                                        (\{ name } ->
                                            ( Name.toCamelCase name, Scala.Variable (Name.toCamelCase name ++ "_") )
                                        )
                                )
                            )
            in
            generatorsResult
                |> Result.map
                    (\generators ->
                        Scala.ForComp generators yieldValue
                            |> decoderLambda [ ( Name.fromString "c", typeRef (Name.fromString "HCursor") circePackagePath [] |> Just ) ]
                    )

        Function a argType returnType ->
            Err "Cannot decode a function"

        Type.Unit a ->
            Scala.Ref [ "morphir", "sdk", "basics", "Codec" ] "decodeUnit"
                |> Ok

        ExtensibleRecord a name fields ->
            let
                generatorsResult : Result Error (List Scala.Generator)
                generatorsResult =
                    fields
                        |> List.map
                            (\field ->
                                mapTypeToDecoderReference Nothing field.tpe
                                    |> Result.map
                                        (\fieldValueDecoder ->
                                            let
                                                downFieldApply : Scala.Value
                                                downFieldApply =
                                                    downField c (field.name |> Name.toCamelCase)

                                                forCompFieldRHS : Scala.Value
                                                forCompFieldRHS =
                                                    circeAs downFieldApply fieldValueDecoder

                                                forCompField : Scala.Generator
                                                forCompField =
                                                    Scala.Extract (Scala.NamedMatch (field.name |> Name.toCamelCase)) forCompFieldRHS
                                            in
                                            forCompField
                                        )
                            )
                        |> ResultList.keepFirstError

                yieldArgs : List Scala.ArgValue
                yieldArgs =
                    fields
                        |> List.map
                            (\field ->
                                Scala.ArgValue Nothing (Scala.Variable (Name.toCamelCase field.name))
                            )

                yieldValue : Scala.Value
                yieldValue =
                    maybeTypeNameAndPath
                        |> Maybe.map (\( n, path ) -> Scala.Apply (Scala.Ref path (n |> Name.toTitleCase)) yieldArgs)
                        |> Maybe.withDefault
                            (Scala.StructuralValue
                                (fields
                                    |> List.map
                                        (\field ->
                                            ( Name.toCamelCase field.name, Scala.Variable (Name.toCamelCase field.name) )
                                        )
                                )
                            )
            in
            generatorsResult
                |> Result.map
                    (\generators ->
                        Scala.ForComp generators yieldValue
                            |> decoderLambda [ ( Name.fromString "c", typeRef (Name.fromString "HCursor") circePackagePath [] |> Just ) ]
                    )



-- Circe API


c =
    Scala.Variable "c"


circeAs : Scala.Value -> Scala.Value -> Scala.Value
circeAs cursor decoder =
    Scala.Apply (Scala.Select cursor "as")
        [ Scala.ArgValue Nothing
            decoder
        ]


downField : Scala.Value -> Scala.Name -> Scala.Value
downField cursor fieldName =
    Scala.Apply
        (Scala.Select cursor "downField")
        [ Scala.ArgValue Nothing
            (Scala.Literal (Scala.StringLit fieldName))
        ]


downN : Scala.Value -> Int -> Scala.Value
downN cursor n =
    Scala.Apply
        (Scala.Select cursor "downN")
        [ Scala.ArgValue Nothing
            (Scala.Literal (Scala.IntegerLit n))
        ]

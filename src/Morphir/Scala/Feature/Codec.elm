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
                        mapTypeDefinitionToDecoder currentPackagePath currentModulePath types
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
    let
        ( scalaTypePath, scalaName ) =
            ScalaBackend.mapFQNameToPathAndName (FQName.fQName currentPackagePath currentModulePath typeName)

        patternMatch : Type.Constructors a -> Result Error (List ( Scala.Pattern, Scala.Value ))
        patternMatch ctors =
            ctors
                |> Dict.toList
                |> List.map
                    (\( ctorName, ctorArgs ) ->
                        mapConstructorsToEncoders scalaTypePath ( currentPackagePath, currentModulePath, ctorName ) ctorArgs
                    )
                |> ResultList.keepFirstError

        scalaDeclaration : Scala.Value -> List (Scala.Annotated Scala.MemberDecl)
        scalaDeclaration scalaValue =
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
                        scalaValue
                    }
                )
            ]
    in
    case accessControlledDocumentedTypeDef.value.value of
        Type.TypeAliasDefinition _ typeExp ->
            mapTypeToEncoderReference scalaName scalaTypePath typeExp
                |> Result.map scalaDeclaration

        Type.CustomTypeDefinition typeParams accessControlledCtors ->
            patternMatch accessControlledCtors.value
                |> Result.map Scala.MatchCases
                |> Result.map (Scala.Match (Scala.Variable (scalaName |> Name.toCamelCase)))
                |> Result.map (scalaLambda scalaName scalaTypePath)
                |> Result.map scalaDeclaration



{-
   This function maps a custom type definition to a Scala encoder
-}


mapConstructorsToEncoders : Scala.Path -> FQName -> List ( Name, Type ta ) -> Result Error ( Scala.Pattern, Scala.Value )
mapConstructorsToEncoders tpePath (( _, _, ctorName ) as fqName) ctorArgs =
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

    Maps a Morphir Type Definition to a Decoder

-}
mapTypeDefinitionToDecoder : Package.PackageName -> Path -> ( Name, AccessControlled (Documented (Type.Definition ta)) ) -> Result Error (List (Scala.Annotated Scala.MemberDecl))
mapTypeDefinitionToDecoder currentPackagePath currentModulePath ( typeName, accessControlledDocumentedTypeDef ) =
    let
        ( scalaTypePath, scalaName ) =
            ScalaBackend.mapFQNameToPathAndName (FQName.fQName currentPackagePath currentModulePath typeName)

        scalaDeclaration : Scala.Value -> List (Scala.Annotated Scala.MemberDecl)
        scalaDeclaration scalaValue =
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
                    , value =
                        scalaValue
                    }
                )
            ]
    in
    case accessControlledDocumentedTypeDef.value.value of
        Type.TypeAliasDefinition typeArgs typeExp ->
            mapTypeToDecoderReference (FQName.fQName currentPackagePath currentModulePath typeName) scalaName typeExp
                |> Result.map
                    (Scala.Lambda [ ( "c", Just (Scala.TypeRef [ "io.circe" ] "HCursor") ) ])
                |> Result.map scalaDeclaration

        Type.CustomTypeDefinition typeParams accessControlledCtors ->
            let
                patternMatchResult : Result Error (List ( Scala.Pattern, Scala.Value ))
                patternMatchResult =
                    accessControlledCtors.value
                        |> Dict.toList
                        |> List.map
                            (\( ctorName, ctorArgs ) ->
                                mapConstructorsToDecoder ( currentPackagePath, currentModulePath, ctorName ) ctorArgs scalaName
                            )
                        |> ResultList.keepFirstError

                hCursor =
                    "c"

                downApply =
                    hCursor ++ ".downN(0)" ++ ".as[String]" ++ ".flatMap"

                scalaValueResult : Result Error Scala.Value
                scalaValueResult =
                    patternMatchResult
                        |> Result.map
                            (\patternMatch ->
                                Scala.Lambda [ ( "c", Just (Scala.TypeRef [ "io", "circe" ] "HCursor") ) ]
                                    (Scala.Apply
                                        (Scala.Variable downApply)
                                        [ Scala.ArgValue Nothing (Scala.Lambda [ ( "tag", Nothing ) ] (Scala.Match (Scala.Variable "tag") (Scala.MatchCases patternMatch))) ]
                                    )
                            )
            in
            Result.map (\scalaValue -> scalaDeclaration scalaValue) scalaValueResult


mapConstructorsToDecoder : FQName -> List ( Name, Type ta ) -> Name -> Result Error ( Scala.Pattern, Scala.Value )
mapConstructorsToDecoder (( _, _, ctorName ) as fqName) ctorArgs name =
    let
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
                                mapTypeToDecoderReference fqName name (Tuple.second arg)
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
                    ( Scala.LiteralMatch (Scala.StringLit (name |> Name.toTitleCase))
                    , Scala.ForComp generators yeildExpression
                    )
                )


scalaLambda : Name -> Scala.Path -> Scala.Value -> Scala.Value
scalaLambda tpeName tpePath body =
    Scala.Lambda
        [ ( tpeName
                |> Name.toCamelCase
          , Just (Scala.TypeRef tpePath (tpeName |> Name.toTitleCase))
          )
        ]
        body


{-|

    Get an Encoder reference for a Type

-}
mapTypeToEncoderReference : Name -> Scala.Path -> Type ta -> Result Error Scala.Value
mapTypeToEncoderReference tpeName tpePath tpe =
    case tpe of
        Type.Variable _ varName ->
            Scala.Variable ("encode" :: varName |> Name.toCamelCase)
                |> scalaLambda tpeName tpePath
                |> Ok

        -- Assuming that the encoders for a reference have already been handled. We just have to return the encoder reference
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

                scalaReference : List String -> String -> Scala.Value
                scalaReference path name =
                    Scala.Ref path name
            in
            Ok <| scalaReference codecPath encoderName

        Type.Tuple a types ->
            let
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
                        Scala.Apply (Scala.Variable "io.circe.arr") argVal
                            |> scalaLambda tpeName tpePath
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
                |> Result.map (scalaLambda tpeName tpePath)

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
            objRef |> Result.map (scalaLambda tpeName tpePath)

        Type.Function a argType returnType ->
            Err "Cannot encode a function"

        Type.Unit a ->
            Scala.Unit
                |> scalaLambda tpeName tpePath
                |> Ok


{-|

    Get an Decoder reference for a Type

-}
mapTypeToDecoderReference : FQName -> Name -> Type ta -> Result Error Scala.Value
mapTypeToDecoderReference fqName tpeName tpe =
    case tpe of
        Type.Variable _ varName ->
            Scala.Variable ("decode" :: varName |> Name.toCamelCase)
                |> Ok

        Type.Reference _ (( packageName, moduleName, typeName ) as fqnName) typeArgs ->
            let
                scalaPackageName =
                    packageName ++ moduleName |> List.map (Name.toCamelCase >> String.toLower)

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
            Ok (scalaReference codecPath decoderName)

        Type.Tuple a types ->
            let
                decodedTypesResult =
                    types
                        |> List.map
                            (\currentType ->
                                mapTypeToDecoderReference fqName tpeName currentType
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
                                mapTypeToDecoderReference fqName tpeName field.tpe
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
                        Scala.ForComp generators (Scala.Apply (Scala.Ref path (scalaName |> Name.toTitleCase)) yieldValue)
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
                                mapTypeToDecoderReference fqName name field.tpe
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

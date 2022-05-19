module Morphir.Scala.Feature.Codec exposing (..)

import Dict
import List
import List.Extra as ListExtra
import Morphir.IR.AccessControlled exposing (Access(..), AccessControlled)
import Morphir.IR.Distribution exposing (Distribution)
import Morphir.IR.Documented exposing (Documented)
import Morphir.IR.FQName as FQName exposing (FQName)
import Morphir.IR.Module as Module exposing (ModuleName)
import Morphir.IR.Name as Name exposing (Name)
import Morphir.IR.Package as Package
import Morphir.IR.Path as Path exposing (Path)
import Morphir.IR.Type as Type exposing (Type(..))
import Morphir.IR.Value as Value exposing (Pattern(..), Value(..))
import Morphir.SDK.ResultList as ResultList
import Morphir.Scala.AST as Scala exposing (Annotated)
import Morphir.Scala.Backend exposing (Options)
import Morphir.Scala.Feature.Core as ScalaBackend exposing (mapFQNameToPathAndName, mapTypeMember)


type alias Error =
    String


mapModuleDefinitionToCodecs : Options -> Distribution -> Package.PackageName -> Path -> AccessControlled (Module.Definition ta (Type ())) -> List Scala.CompilationUnit
mapModuleDefinitionToCodecs opt distribution currentPackagePath currentModulePath accessControlledModuleDef =
    let
        ( scalaPackagePath, moduleName ) =
            case currentModulePath |> List.reverse of
                [] ->
                    ( [], [] )

                lastName :: reverseModulePath ->
                    ( List.append (currentPackagePath |> List.map (Name.toCamelCase >> String.toLower)) (reverseModulePath |> List.reverse |> List.map (Name.toCamelCase >> String.toLower)), lastName )

        typeMembers : List (Scala.Annotated Scala.MemberDecl)
        typeMembers =
            accessControlledModuleDef.value.types
                |> Dict.toList
                |> List.concatMap
                    (\types ->
                        mapTypeDefinitionToEncoder currentPackagePath currentModulePath accessControlledModuleDef types
                            |> Result.withDefault []
                    )

        moduleUnit : Scala.CompilationUnit
        moduleUnit =
            { dirPath = scalaPackagePath
            , fileName = (moduleName |> Name.toTitleCase) ++ ".scala"
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
                                moduleName |> Name.toTitleCase
                            , members =
                                typeMembers
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
        Type.TypeAliasDefinition typeArgs typeExp ->
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

        Type.CustomTypeDefinition typeArgs accessControlledConstructors ->
            Debug.todo "Implement"


{-|

    Maps a Morphir Type Definition to a Decoder

-}
mapTypeDefinitionToDecoder : FQName -> Type.Definition () -> Result Error (List (Scala.Annotated Scala.MemberDecl))
mapTypeDefinitionToDecoder (( packageName, moduleName, typeName ) as fQTypeName) typeDef =
    case typeDef of
        Type.TypeAliasDefinition typeArgs typeExp ->
            let
                ( scalaTypePath, scalaName ) =
                    ScalaBackend.mapFQNameToPathAndName fQTypeName
            in
            genDecodeReference fQTypeName typeExp
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

        Type.CustomTypeDefinition typeArgs accessControlledConstructors ->
            Debug.todo "Implement"


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
                        (scalaPackageName ++ [ scalaModuleName ])
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
genDecodeReference : FQName -> Type () -> Result Error Scala.Value
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

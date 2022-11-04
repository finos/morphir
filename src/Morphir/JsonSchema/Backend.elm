module Morphir.JsonSchema.Backend exposing (..)

{-| This module encapsulates the JSON Schema backend. It takes the Morphir IR as the input and returns an in-memory
representation of files generated. The consumer is responsible for getting the input IR and saving the output
to the file-system.
-}

{-
   Copyright 2020 Morgan Stanley

   Licensed under the Apache License, Version 2.0 (the "License");
   you may not use this file except in compliance with the License.
   You may obtain a copy of the License at

       http://www.apache.org/licenses/LICENSE-2.0

   Unless required by applicable law or agreed to in writing, software
   distributed under the License is distributed on an "AS IS" BASIS,
   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
   See the License for the specific language governing permissions and
   limitations under the License.
-}

import Dict exposing (Dict)
import Morphir.File.FileMap exposing (FileMap)
import Morphir.IR.AccessControlled exposing (AccessControlled)
import Morphir.IR.Distribution as Distribution exposing (Distribution)
import Morphir.IR.FQName as FQName exposing (FQName)
import Morphir.IR.Module as Module exposing (ModuleName)
import Morphir.IR.Name as Name exposing (Name)
import Morphir.IR.Package as Package exposing (PackageName)
import Morphir.IR.Path as Path exposing (Path)
import Morphir.IR.Type as Type exposing (Type)
import Morphir.JsonSchema.AST exposing (ArrayType(..), Derivative(..), Schema, SchemaType(..), TypeName)
import Morphir.JsonSchema.PrettyPrinter exposing (encodeSchema)
import Morphir.SDK.ResultList as ResultList


type alias Options =
    {}


type alias QualifiedName =
    ( Path, Name )


type alias Error =
    String


{-| Entry point for the JSON Schema backend. It takes the Morphir IR as the input and returns an in-memory
representation of files generated.
-}
mapDistribution : Options -> Distribution -> Result Error FileMap
mapDistribution _ distro =
    case distro of
        Distribution.Library packageName _ packageDef ->
            mapPackageDefinition packageName packageDef


mapPackageDefinition : PackageName -> Package.Definition ta (Type ()) -> Result Error FileMap
mapPackageDefinition packageName packageDefinition =
    packageDefinition
        |> generateSchema packageName
        |> Result.map encodeSchema
        |> Result.map (Dict.singleton ( [], Path.toString Name.toTitleCase "." packageName ++ ".json" ))


mapQualifiedName : ( Path, Name ) -> String
mapQualifiedName ( path, name ) =
    String.join "." [ Path.toString Name.toTitleCase "." path, Name.toTitleCase name ]


generateSchema : PackageName -> Package.Definition ta (Type ()) -> Result Error Schema
generateSchema packageName packageDefinition =
    let
        schemaTypeDefinitions : Result Error (List ( TypeName, SchemaType ))
        schemaTypeDefinitions =
            packageDefinition.modules
                |> Dict.toList
                |> List.map
                    (\( modName, modDef ) ->
                        extractTypes modName modDef.value
                            |> List.map
                                (\( qualifiedName, typeDef ) ->
                                    mapTypeDefinition qualifiedName typeDef
                                )
                            |> ResultList.keepFirstError
                            |> Result.map List.concat
                    )
                |> ResultList.keepFirstError
                |> Result.map List.concat
    in
    schemaTypeDefinitions
        |> Result.map
            (\definitions ->
                { id = "https://morphir.finos.org/" ++ Path.toString Name.toSnakeCase "-" packageName ++ ".schema.json"
                , schemaVersion = "https://json-schema.org/draft/2020-12/schema"
                , definitions = definitions |> Dict.fromList
                }
            )


extractTypes : ModuleName -> Module.Definition ta (Type ()) -> List ( QualifiedName, Type.Definition ta )
extractTypes modName definition =
    definition.types
        |> Dict.toList
        |> List.map
            (\( name, accessControlled ) ->
                ( ( modName, name ), accessControlled.value.value )
            )


mapTypeDefinition : ( Path, Name ) -> Type.Definition ta -> Result Error (List ( TypeName, SchemaType ))
mapTypeDefinition (( path, name ) as qualifiedName) definition =
    case definition of
        Type.TypeAliasDefinition _ typ ->
            mapType typ
                |> Result.map (\schemaType -> [ ( mapQualifiedName qualifiedName, schemaType ) ])

        Type.CustomTypeDefinition _ accessControlledCtors ->
            let
                oneOfs2 =
                    accessControlledCtors.value
                        |> Dict.toList
                        |> List.map
                            (\( ctorName, ctorArgs ) ->
                                let
                                    ctorNameString =
                                        ctorName |> Name.toTitleCase
                                in
                                if List.isEmpty ctorArgs then
                                    Ok (Const ctorNameString)

                                else
                                    (ctorArgs
                                        |> List.map
                                            (\tpe ->
                                                mapType (Tuple.second tpe)
                                            )
                                    )
                                        |> ResultList.keepFirstError
                                        |> Result.map
                                            (\schemaType ->
                                                Array
                                                    (TupleType
                                                        (Const (ctorName |> Name.toTitleCase)
                                                            :: schemaType
                                                        )
                                                        ((ctorArgs |> List.length) + 1)
                                                    )
                                                    False
                                            )
                            )
                        |> ResultList.keepFirstError
            in
            oneOfs2
                |> Result.map
                    (\schemaType -> [ ( (path |> Path.toString Name.toTitleCase ".") ++ "." ++ (name |> Name.toTitleCase), OneOf schemaType ) ])


mapType : Type ta -> Result Error SchemaType
mapType typ =
    case typ of
        Type.Reference _ (( packageName, moduleName, localName ) as fQName) argTypes ->
            case ( FQName.toString fQName, argTypes ) of
                ( "Morphir.SDK:Basics:int", [] ) ->
                    Ok Integer

                ( "Morphir.SDK:Decimal:decimal", [] ) ->
                    Ok (String DecimalString)

                ( "Morphir.SDK:String:string", [] ) ->
                    Ok (String BasicString)

                ( "Morphir.SDK:Char:char", [] ) ->
                    Ok (String CharString)

                ( "Morphir.SDK:LocalDate:localDate", [] ) ->
                    Ok (String DateString)

                ( "Morphir.SDK:LocalTime:localTime", [] ) ->
                    Ok (String TimeString)

                ( "Morphir.SDK:Month:month", [] ) ->
                    Ok (String MonthString)

                ( "Morphir.SDK:Basics:float", [] ) ->
                    Ok Number

                ( "Morphir.SDK:Tuple:tuple", [] ) ->
                    Ok Number

                ( "Morphir.SDK:Basics:bool", [] ) ->
                    Ok Boolean

                ( "Morphir.SDK:List:list", [ itemType ] ) ->
                    Result.map2 Array
                        (mapType itemType
                            |> Result.map ListType
                        )
                        (Ok False)

                ( "Morphir.SDK:Set:set", [ itemType ] ) ->
                    Result.map2 Array
                        (mapType itemType
                            |> Result.map ListType
                        )
                        (Ok True)

                ( "Morphir.SDK:Maybe:maybe", [ itemType ] ) ->
                    mapType itemType
                        |> Result.map
                            (\schemaItemType ->
                                OneOf
                                    [ Null
                                    , schemaItemType
                                    ]
                            )

                _ ->
                    Ok
                        (Ref
                            (String.concat
                                [ "#/$defs/"
                                , moduleName |> Path.toString Name.toTitleCase "."
                                , "."
                                , localName |> Name.toTitleCase
                                ]
                            )
                        )

        Type.Record _ fields ->
            fields
                |> List.map
                    (\field ->
                        mapType field.tpe
                            |> Result.map (\fieldSchemaType -> ( Name.toCamelCase field.name, fieldSchemaType ))
                    )
                |> ResultList.keepFirstError
                |> Result.map (Dict.fromList >> Object)

        _ ->
            Err "Cannot map this type"

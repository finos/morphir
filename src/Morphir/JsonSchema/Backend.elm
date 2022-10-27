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
import Morphir.JsonSchema.AST exposing (ArrayType(..), Schema, SchemaType(..), TypeName)
import Morphir.JsonSchema.PrettyPrinter exposing (encodeSchema)


type alias Options =
    {}


type alias QualifiedName =
    ( Path, Name )


type Error
    = Error String


{-| Entry point for the JSON Schema backend. It takes the Morphir IR as the input and returns an in-memory
representation of files generated.
-}
mapDistribution : Options -> Distribution -> FileMap
mapDistribution _ distro =
    case distro of
        Distribution.Library packageName _ packageDef ->
            mapPackageDefinition packageName packageDef


mapPackageDefinition : PackageName -> Package.Definition ta (Type ()) -> FileMap
mapPackageDefinition packageName packageDefinition =
    packageDefinition
        |> generateSchema packageName
        |> encodeSchema
        |> Dict.singleton ( [], Path.toString Name.toTitleCase "." packageName ++ ".json" )


mapQualifiedName : ( Path, Name ) -> String
mapQualifiedName ( path, name ) =
    String.join "." [ Path.toString Name.toTitleCase "." path, Name.toTitleCase name ]


generateSchema : PackageName -> Package.Definition ta (Type ()) -> Schema
generateSchema packageName packageDefinition =
    let
        schemaTypeDefinitions =
            packageDefinition.modules
                |> Dict.foldl
                    (\modName modDef listSoFar ->
                        extractTypes modName modDef.value
                            |> List.concatMap
                                (\( qualifiedName, typeDef ) ->
                                    mapTypeDefinition qualifiedName typeDef
                                )
                            |> (\lst -> listSoFar ++ lst)
                    )
                    []
                |> Dict.fromList
    in
    { dirPath = []
    , fileName = ""
    , id = "https://morphir.finos.org/" ++ Path.toString Name.toSnakeCase "-" packageName ++ ".schema.json"
    , schemaVersion = "https://json-schema.org/draft/2020-12/schema"
    , definitions = schemaTypeDefinitions
    }


extractTypes : ModuleName -> Module.Definition ta (Type ()) -> List ( QualifiedName, Type.Definition ta )
extractTypes modName definition =
    definition.types
        |> Dict.toList
        |> List.map
            (\( name, accessControlled ) ->
                ( ( modName, name ), accessControlled.value.value )
            )


mapTypeDefinition : ( Path, Name ) -> Type.Definition ta -> List ( TypeName, SchemaType )
mapTypeDefinition (( path, name ) as qualifiedName) definition =
    case definition of
        Type.TypeAliasDefinition _ typ ->
            [ ( mapQualifiedName qualifiedName
              , case mapType typ of
                    Ok val ->
                        val

                    _ ->
                        Null
              )
            ]

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
                                    Const ctorNameString

                                else
                                    Array
                                        (TupleType
                                            (Const (ctorName |> Name.toTitleCase)
                                                :: (-- begin
                                                    ctorArgs
                                                        |> List.map
                                                            (\x ->
                                                                case mapType (Tuple.second x) of
                                                                    Ok val ->
                                                                        val

                                                                    _ ->
                                                                        Null
                                                            )
                                                   )
                                             -- end
                                            )
                                            ((ctorArgs |> List.length) + 1)
                                        )
                                        False
                            )
            in
            [ ( (path |> Path.toString Name.toTitleCase ".") ++ "." ++ (name |> Name.toTitleCase), OneOf oneOfs2 ) ]


mapType : Type ta -> Result Error SchemaType
mapType typ =
    case typ of
        Type.Reference _ (( packageName, moduleName, localName ) as fQName) argTypes ->
            case ( FQName.toString fQName, argTypes ) of
                ( "Morphir.SDK:Basics:int", [] ) ->
                    Ok Integer

                ( "Morphir.SDK:Decimal:decimal", [] ) ->
                    Ok String

                ( "Morphir.SDK:String:string", [] ) ->
                    Ok String

                ( "Morphir.SDK:Char:char", [] ) ->
                    Ok String

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
                    Ok
                        (OneOf
                            [ Null
                            , case mapType itemType of
                                Ok val ->
                                    val

                                _ ->
                                    Null
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
                |> List.foldl
                    (\field ->
                        \dictSofar ->
                            Dict.insert
                                (Name.toTitleCase field.name)
                                (case mapType field.tpe of
                                    Ok val ->
                                        val

                                    _ ->
                                        Null
                                )
                                dictSofar
                    )
                    Dict.empty
                |> Object
                |> Ok

        _ ->
            Err (Error "Cannot map this type")

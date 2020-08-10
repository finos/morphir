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


module SlateX.DevBot.Proto2.SlateXToProto2.Modules exposing (..)


import Set
import Dict
import SlateX.AST.Name exposing (Name)
import SlateX.AST.Path exposing (Path)
import SlateX.AST.Package exposing (Package)
import SlateX.AST.Module as M
import SlateX.AST.Type as T
import SlateX.DevBot.Proto2.AST as P
import SlateX.Mapping.Naming as Naming


mapInterface : Package -> Path -> M.Interface -> List P.ProtoFile
mapInterface package modulePath moduleInt =
    let
        enums =
            moduleInt.unionTypes
                |> Dict.toList
                |> List.filterMap
                    (\( typeName, unionType ) ->
                        let
                            isEnum =
                                unionType.cases
                                    |> List.all (Tuple.second >> List.isEmpty)
                        in
                        if isEnum then
                            let
                                enum =
                                    P.Enum 
                                        { name = Naming.toTitleCase typeName
                                        , values =
                                            unionType.cases
                                                |> List.indexedMap
                                                    (\index ( caseName, _ ) ->
                                                        ( caseName |> Naming.toSnakeCase |> String.toUpper
                                                        , index
                                                        )
                                                    )
                                        }
                            in
                            Just enum
                        else
                            Nothing    
                    )
        
        messages =
            moduleInt.typeAliases
                |> Dict.toList
                |> List.filterMap
                    (\( typeName, typeAlias ) ->
                        case typeAlias.exp of
                            T.Record fields ->
                                let
                                    message =
                                        P.Message
                                            { name = Naming.toTitleCase typeName
                                            , members =
                                                fields
                                                    |> List.indexedMap
                                                        (\index ( fieldName, fieldType ) ->
                                                            P.Field (mapField fieldName fieldType (index + 1))
                                                        )
                                            }
                                in
                                Just message

                            _ ->
                                Nothing    
                    )
    in
    [ P.ProtoFile (enums ++ messages) ]


mapField : Name -> T.Exp -> Int -> P.FieldDecl
mapField fieldName fieldType fieldNumber =
    let
        mapType tpe =
            case tpe of
                T.Constructor ( [ [ "slate", "x" ], [ "core" ], [ "maybe" ] ], [ "maybe" ] ) [ itemType ] ->
                    let
                        ( _, itemValueType, comment ) =
                            mapType itemType
                    in
                    ( P.Optional, itemValueType, comment )        

                T.Constructor ( [ [ "slate", "x" ], [ "core" ], [ "list" ] ], [ "list" ] ) [ itemType ] ->
                    let
                        ( _, itemValueType, comment ) =
                            mapType itemType
                    in
                    ( P.Repeated, itemValueType, comment )        

                _ ->
                    ( P.Required, P.String, Just ("Unknown field type: " ++ Debug.toString fieldType) )

        ( rule, valueType, topComment ) =
            mapType fieldType            
    in
    { rule = rule
    , tpe = valueType
    , name = Naming.toSnakeCase fieldName
    , number = fieldNumber
    , comment = topComment
    }

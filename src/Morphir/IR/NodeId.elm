module Morphir.IR.NodeId exposing (..)

import Morphir.IR.FQName as FQName exposing (FQName)
import Morphir.IR.Module exposing (ModuleName)
import Morphir.IR.Name as Name
import Morphir.IR.Path as Path exposing (Path)


type NodeID
    = TypeID FQName
    | ValueID FQName
    | ModuleID ModuleName


nodeIdFromString : String -> Result String NodeID
nodeIdFromString str =
    case String.split ":" str |> List.head of
        Just prefix ->
            case prefix of
                "Value" ->
                    let
                        splitNodeString =
                            String.split ":" str |> List.drop 1
                    in
                    case splitNodeString of
                        packageName :: moduleName :: localName :: [] ->
                            Ok (ValueID (FQName.fqn packageName moduleName localName))

                        _ ->
                            Err <| "Value Not Valid"

                "Type" ->
                    let
                        splitNodeString =
                            String.split ":" str |> List.drop 1
                    in
                    case splitNodeString of
                        packageName :: moduleName :: localName :: [] ->
                            Ok (TypeID (FQName.fqn packageName moduleName localName))

                        _ ->
                            Err <| "Type Not Valid"

                "Module" ->
                    let
                        splitNodeString =
                            String.split ":" str |> List.drop 1 |> List.map Name.fromString
                    in
                    case splitNodeString of
                        moduleName ->
                            Ok (ModuleID (Path.fromList moduleName))

                _ ->
                    Err <| "Invalid NodeId: " ++ str

        Nothing ->
            Err <| "Empty prefix"


nodeIdToString : NodeID -> String
nodeIdToString nodeId =
    case nodeId of
        TypeID fQName ->
            String.concat [ "Type:", FQName.toString fQName ]

        ValueID fQName ->
            String.concat [ "Value:", FQName.toString fQName ]

        ModuleID moduleName ->
            String.concat [ "Module:", Path.toString Name.toTitleCase "." moduleName ]

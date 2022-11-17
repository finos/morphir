module Morphir.IR.NodeId exposing (..)

import Morphir.IR.FQName as FQName exposing (FQName)


type NodeID
    = TypeID FQName
    | ValueID FQName


nodeIdFromString : String -> Result String NodeID
nodeIdFromString str =
    case String.split ":" str of
        nodeType :: packageName :: moduleName :: localName :: [] ->
            let
                fqn : FQName
                fqn =
                    FQName.fqn packageName moduleName localName
            in
            case nodeType of
                "Type" ->
                    Ok <| TypeID fqn

                "Value" ->
                    Ok <| ValueID fqn

                _ ->
                    Err <| "Unknown Node type: " ++ nodeType

        _ ->
            Err <| "Invalid NodeId: " ++ str


nodeIdToString : NodeID -> String
nodeIdToString nodeId =
    case nodeId of
        TypeID fQName ->
            String.concat [ "Type:", FQName.toString fQName ]

        ValueID fQName ->
            String.concat [ "Value:", FQName.toString fQName ]

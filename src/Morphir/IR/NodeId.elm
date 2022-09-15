module Morphir.IR.NodeId exposing (..)

import Morphir.IR.FQName as FQName exposing (FQName)


type NodeID
    = TypeID FQName
    | ValueID FQName


nodeIdFromString : String -> NodeID
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
                    TypeID fqn

                "Value" ->
                    ValueID fqn

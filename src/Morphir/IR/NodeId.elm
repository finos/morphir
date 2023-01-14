module Morphir.IR.NodeId exposing (..)

import Morphir.IR.FQName as FQName exposing (FQName)
import Morphir.IR.Module exposing (ModuleName)
import Morphir.IR.Name as Name
import Morphir.IR.Package exposing (PackageName)
import Morphir.IR.Path as Path
import Morphir.IR.QName as QName exposing (QName)


type alias QualifiedName =
    ( PackageName, ModuleName )


type NodeID
    = TypeID FQName
    | ValueID FQName
    | ModuleID ModuleName


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

        ModuleID moduleName ->
            String.concat [ "Module: ", Path.toString Name.toTitleCase "." moduleName ]

module Morphir.IR.NodeId exposing (..)

import Morphir.IR.FQName as FQName exposing (FQName)
import Morphir.IR.Name as Name
import Morphir.IR.Path as Path exposing (Path)


type alias QualifiedName =
    ( Path, Path )


type NodeID
    = TypeID FQName
    | ValueID FQName
    | ModuleID QualifiedName


nodeIdFromString : String -> Result String NodeID
nodeIdFromString str =
    case String.split ":" str of
        [ "Value", packageName, moduleName, localName ] ->
            Ok (ValueID (FQName.fqn packageName moduleName localName))

        [ "Type", packageName, moduleName, localName ] ->
            Ok (TypeID (FQName.fqn packageName moduleName localName))

        [ "Module", packageName, moduleName ] ->
            Ok (ModuleID ( [ packageName |> Name.fromString ], [ moduleName |> Name.fromString ] ))

        _ ->
            Err <| "Invalid NodeId" ++ str


nodeIdToString : NodeID -> String
nodeIdToString nodeId =
    case nodeId of
        TypeID fQName ->
            String.concat [ "Type:", FQName.toString fQName ]

        ValueID fQName ->
            String.concat [ "Value:", FQName.toString fQName ]

        ModuleID ( packageName, moduleName ) ->
            String.join ":"
                [ "Module"
                , Path.toString Name.toTitleCase "." packageName
                , Path.toString Name.toTitleCase "." moduleName
                ]

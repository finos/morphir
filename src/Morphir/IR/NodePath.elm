module Morphir.IR.NodePath exposing (..)

import Morphir.IR.Name as Name exposing (Name)


{-| Represents a path in the IR. This is a recursive structure made up of the following
building blocks:

  - **ChildByName** traverses to a child node by name. It takes one argument
      - the name of the edge to follow (this will usually be a field name)
  - **ChildByIndex** traverses to a child node by index. It takes one argument
      - the index of the child node (the list of children will be determined by the type of the node that we are currently on)

The path should be constructed in a reverse order: the node at the top will be the last step in the path

Example usage:

    type alias Foo =
        { field1 : Bool
        , field2 :
            { field1 : Int
            , field2 : ( String, Float )
            }
        }

    NodePath.fromList [] -- Refers to type "Foo" itself

    NodePath.fromList [ ChildByName "field1" ] -- Refers to Bool

    NodePath.fromList [ ChildByName "field2", ChildByName "field1" ] -- Refers to Int

    NodePath.fromList [ ChildByName "field2", ChildByName "field2", ChildByIndex 1 ] -- Refers to Float

-}
type alias NodePath =
    NodePath (List NodePathStep)


type NodePathStep
    = ChildByName Name
    | ChildByIndex Int


toString : NodePath -> String
toString nodePath =
    nodePath
        |> List.map
            (\pathStep ->
                case pathStep of
                    ChildByName name ->
                        Name.toCamelCase name

                    ChildByIndex index ->
                        String.fromInt index
            )
        |> String.join "."


fromString : String -> NodePath
fromString string =
    string
        |> String.split "."
        |> List.map
            (\stepString ->
                case String.toInt stepString of
                    Just index ->
                        ChildByIndex index

                    Nothing ->
                        ChildByName (Name.fromString stepString)
            )

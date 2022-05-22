module Morphir.IR.Attribute exposing (..)

import Dict exposing (Dict)
import Morphir.Elm.ModuleName exposing (ModuleName)
import Morphir.IR.Name exposing (Name)
import Morphir.IR.Package as Package


type alias PackageAttributes ta va =
    { modules : Dict ModuleName (ModuleAttributes ta va)
    }


type alias ModuleAttributes ta va =
    { types : Dict Name (AttributeTree ta)
    , values : Dict Name (AttributeTree va)
    }


{-| Compact representation of a set of optional attributes on some nodes of an expression tree.
-}
type AttributeTree a
    = AttributeTree a (List ( NodePath, AttributeTree a ))


{-| Represents a path in a type or value expression tree. This is a recursive structure made up of the following
building blocks:

  - **ChildNodeByName** traverses to a child node by name. It takes two arguments
      - the name of the edge to follow (this will usually be a field name)
      - the rest of the path (this is where the recursion happens)
  - **ChildNodeByIndex** traverses to a child node by index. It takes two arguments
      - the index of the child node (the list of children will be determined by the type of the node that we are currently on)
      - the rest of the path (this is where the recursion happens)
  - **CurrentNode** stops at the current node (this is where the recursion ends)

Example usage:

    type alias Foo =
        { field1 : Bool
        , field2 :
            { field1 : Int
            , field2 : ( String, Float )
            }
        }

    CurrentNode -- Refers to type "Foo" itself

    ChildNodeByName "field1" CurrentNode -- Refers to Bool

    ChildNodeByName "field2" (ChildNodeByName "field1" CurrentNode) -- Refers to Int

    ChildNodeByName "field2" (ChildNodeByName "field2" (ChildNodeByIndex 1 CurrentNode)) -- Refers to Float

-}
type NodePath
    = CurrentNode
    | ChildNodeByName Name NodePath
    | ChildNodeByIndex Int NodePath


detach : Package.Definition (Maybe ta) (Maybe va) -> ( Package.Definition () (), PackageAttributes ta va )
detach =
    Debug.todo "implement"


attach : Package.Definition () () -> PackageAttributes ta va -> Package.Definition (Maybe ta) (Maybe va)
attach =
    Debug.todo "implement"


withDefaultTypeAnnotation : ta -> Package.Definition (Maybe ta) va -> Package.Definition ta va
withDefaultTypeAnnotation =
    Debug.todo "implement"


withDefaultValueAnnotation : va -> Package.Definition ta (Maybe va) -> Package.Definition ta va
withDefaultValueAnnotation =
    Debug.todo "implement"

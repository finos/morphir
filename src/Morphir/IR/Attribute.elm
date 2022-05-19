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


{-| Represents a path in a type or value expression tree.
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

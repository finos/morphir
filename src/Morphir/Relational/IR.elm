module Morphir.Relational.IR exposing (..)

import Morphir.IR.Name exposing (Name)
import Morphir.IR.Value exposing (TypedValue)


type Relation
    = From Name
    | Where TypedValue Relation
    | Select (List ( Name, TypedValue )) Relation
    | Join JoinType TypedValue Relation Relation


type JoinType
    = Inner
    | Outer OuterJoinType


type OuterJoinType
    = Left
    | Right
    | Full

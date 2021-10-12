module Morphir.Relational.IR exposing (..)

import Morphir.IR.Name exposing (Name)
import Morphir.IR.Value exposing (RawValue)


type Relation
    = From Name
    | Where RawValue Relation
    | Select (List RawValue) Relation
    | Join JoinType RawValue Relation Relation


type JoinType
    = Inner
    | Outer OuterJoinType


type OuterJoinType
    = Left
    | Right
    | Full

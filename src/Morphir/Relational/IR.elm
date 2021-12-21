module Morphir.Relational.IR exposing (..)

import Array exposing (Array)
import Morphir.IR.Name exposing (Name)
import Morphir.IR.Value exposing (RawValue, TypedValue, Value)


type alias FieldName =
    Name


type alias ObjectName =
    Name


type alias FieldValue =
    TypedValue


type alias RelationValue =
    { schema : List FieldName
    , data : List (Array FieldValue)
    }


{-| Represents an expression that yields a relation.
-}
type Relation
    = Values RelationValue
    | From ObjectName
    | Where FieldValue Relation
    | Select (List ( FieldName, FieldValue )) Relation
    | Join JoinType FieldValue Relation Relation


type JoinType
    = Inner
    | Outer OuterJoinType


type OuterJoinType
    = Left
    | Right
    | Full

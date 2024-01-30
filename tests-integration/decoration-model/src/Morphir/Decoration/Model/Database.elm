module Morphir.Decoration.Model.Database exposing (..)


type alias Entity =
    Bool


type alias ColumnName =
    String


type alias TableName =
    String


type alias Table =
    Table TableName


type Column
    = Column ColumnName


type alias Id =
    Bool


type alias GeneratedValue =
    Bool

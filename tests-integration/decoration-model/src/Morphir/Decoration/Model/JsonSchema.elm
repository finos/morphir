module Morphir.Decoration.Model.JsonSchema exposing (..)


type alias SchemaEnabled =
    Bool



-- String Type Decorations


type alias MinLength =
    Int


type alias MaxLength =
    Int


type alias Pattern =
    String


type Format
    = DateTime
    | Time
    | Date
    | Duration
    | Email
    | Hostname
    | Uri



-- number type decorations


type alias Minimum =
    Int


type alias Maximum =
    Int


type alias ExclusiveMinimum =
    Int


type alias ExclusiveMaximum =
    Int


type alias MultiplesOf =
    Int



-- Object Type Decorations


type alias MinProperties =
    Int


type alias MaxProperties =
    String



-- Array Type Decorations


type alias MinContains =
    Int


type alias MaxContains =
    Int


type alias MinItems =
    Int


type alias MaxItems =
    Int


type alias Uniqueness =
    Bool

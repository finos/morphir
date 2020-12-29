module Morphir.Reference.Model.Issues.Issue227 exposing (..)


type alias FloatAlias =
    Float


fun : FloatAlias -> FloatAlias
fun f =
    if f <= 3.14 then
        f

    else
        f

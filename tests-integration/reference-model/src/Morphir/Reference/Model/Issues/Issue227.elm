module Morphir.Reference.Model.Issues.Issue227 exposing (..)

import Morphir.Reference.Model.Issues.Common exposing (FloatAlias)


fun : FloatAlias -> FloatAlias
fun f =
    if f <= 3.14 then
        f

    else
        f

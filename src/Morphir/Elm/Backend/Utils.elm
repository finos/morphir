module Morphir.Elm.Backend.Utils exposing (..)

import Elm.Syntax.Node exposing (Node(..))
import Elm.Syntax.Range exposing (emptyRange)


emptyRangeNode : a -> Node a
emptyRangeNode a =
    Node emptyRange a

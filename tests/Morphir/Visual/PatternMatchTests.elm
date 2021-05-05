module Morphir.Visual.PatternMatchTests exposing (..)

import Element exposing (Attribute, Column, Element, fill, row, spacing, table, text, width)
import Expect
import Morphir.IR.Literal exposing (Literal(..))
import Morphir.IR.Type as Type
import Morphir.IR.Value as Value exposing (Pattern(..), Value(..))
import Test exposing (..)

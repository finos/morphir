module Morphir.IR.Type.Error exposing (..)

import Morphir.IR.Name exposing (Name)
import Morphir.IR.Source as Source


type Expected a
    = Expected a


type Category
    = Category


type PExpected tipe
    = PNoExpectation tipe
    | PFromContext Source.Region PContext tipe


type PContext
    = PTypedArg Name Int
    | PCaseMatch Int
    | PCtorArg Name Int
    | PListEntry Int
    | PTail


type PCategory
    = PRecord
    | PUnit
    | PTuple
    | PList
    | PCtor Name
    | PInt
    | PStr
    | PChr
    | PBool

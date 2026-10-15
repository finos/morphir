module Parity.Modules.Util exposing (Id, empty, one)

import Parity.Modules.Base exposing (base)


type alias Id =
    String


empty : Id
empty =
    ""


one : Int
one =
    base


hidden : Int
hidden =
    2

module Morphir.Type.Constraint exposing (..)

import Morphir.Type.MetaType as MetaType exposing (MetaType)


type Constraint
    = Constraint MetaType MetaType


equivalent : Constraint -> Constraint -> Bool
equivalent (Constraint a1 a2) (Constraint b1 b2) =
    (a1 == b1 && a2 == b2) || (a1 == b2 && a2 == b1)


substitute : MetaType.Variable -> MetaType -> Constraint -> Constraint
substitute var replacement (Constraint metaType1 metaType2) =
    Constraint
        (metaType1 |> MetaType.substitute var replacement)
        (metaType2 |> MetaType.substitute var replacement)

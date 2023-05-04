module Morphir.IR.Values exposing (..)

import Morphir.IR.Literal exposing (Literal(..))
import Morphir.IR.Name as Name
import Morphir.IR.Value as Value exposing (Value)


apply : Value.Value ta () -> Value.Value ta () -> Value.Value ta ()
apply f a1 =
    Value.Apply () f a1


apply2 : Value.Value ta () -> Value.Value ta () -> Value.Value ta () -> Value.Value ta ()
apply2 f a1 a2 =
    Value.Apply () (apply f a1) a2


apply3 : Value.Value ta () -> Value.Value ta () -> Value.Value ta () -> Value.Value ta () -> Value.Value ta ()
apply3 f a1 a2 a3 =
    Value.Apply () (apply2 f a1 a2) a3


apply4 : Value.Value ta () -> Value.Value ta () -> Value.Value ta () -> Value.Value ta () -> Value.Value ta () -> Value.Value ta ()
apply4 f a1 a2 a3 a4 =
    Value.Apply () (apply3 f a1 a2 a3) a4


unit : Value () ()
unit =
    Value.Unit ()


var : String -> Value () ()
var name =
    Value.Variable () (Name.fromString name)


litInt : Int -> Value () ()
litInt v =
    Value.Literal () (WholeNumberLiteral v)


basics : String -> Value () ()
basics localName =
    Value.Reference () ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "basics" ] ], Name.fromString localName )

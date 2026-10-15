module Parity.Signatures.Constrained exposing (double, larger, join, sorted, pairs)


double : number -> number
double n =
    n + n


larger : comparable -> comparable -> comparable
larger a b =
    if a > b then
        a

    else
        b


join : appendable -> appendable -> appendable
join a b =
    a ++ b


sorted : List comparable -> List comparable
sorted items =
    List.sort items


pairs : List a -> List ( a, Bool )
pairs items =
    let
        mark item =
            ( item, True )
    in
    List.map mark items

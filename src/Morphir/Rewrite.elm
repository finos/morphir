module Morphir.Rewrite exposing (Rewrite, topDown, bottomUp)

{-| A rewrite is a special mapping usually applied on typed trees.
It applies rules to various nodes in the tree and returns a new tree.

@docs Rewrite, topDown, bottomUp

-}

import Morphir.Rule as Rule exposing (Rule)


{-| Type that represents a tree rewrite. It's generic in the type of the
tree node. It takes two functions as input: a mapping that's applied to
the children of branch nodes and one that is applied to leaf nodes.
-}
type alias Rewrite a =
    (a -> a) -> (a -> a) -> a -> a


{-| Executes a rewrite using a top-down approach where the rules are
applied to nodes from the root towards the leaf nodes. When a rule does
not match the rewrite continues downward. When a rule matches it's
applied and the rewrite process stops traversing downward in the subtree.
-}
topDown : Rewrite a -> Rule a -> a -> a
topDown rewrite rewriteRule typeToRewrite =
    rewriteRule typeToRewrite
        |> Maybe.withDefault
            (rewrite
                (topDown rewrite rewriteRule)
                identity
                typeToRewrite
            )


{-| Executes a rewrite using a bottom-up approach where the rules are
applied to nodes from the leaf nodes towards the root. Always traverses
the entire tree regardless of rule matches but only changes the tree if
a rule matches.
-}
bottomUp : Rewrite a -> Rule a -> a -> a
bottomUp rewrite rewriteRule =
    rewrite
        (bottomUp rewrite rewriteRule)
        (Rule.defaultToOriginal rewriteRule)

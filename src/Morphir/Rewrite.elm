{-
Copyright 2020 Morgan Stanley

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
-}


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
type alias Rewrite e a =
    (a -> Result e a) -> (a -> Result e a) -> a -> Result e a


{-| Executes a rewrite using a top-down approach where the rules are
applied to nodes from the root towards the leaf nodes. When a rule does
not match the rewrite continues downward. When a rule matches it's
applied and the rewrite process stops traversing downward in the subtree.
-}
topDown : Rewrite e a -> Rule e a -> a -> Result e a
topDown rewrite rewriteRule nodeToRewrite =
    case rewriteRule nodeToRewrite of
        Nothing ->
            rewrite
                (topDown rewrite rewriteRule)
                (\a -> Ok a)
                nodeToRewrite

        Just result ->
            result


{-| Executes a rewrite using a bottom-up approach where the rules are
applied to nodes from the leaf nodes towards the root. Always traverses
the entire tree regardless of rule matches but only changes the tree if
a rule matches.
-}
bottomUp : Rewrite e a -> Rule e a -> a -> Result e a
bottomUp rewrite rewriteRule nodeToRewrite =
    let
        top : Result e a
        top =
            rewrite
                (\a -> bottomUp rewrite rewriteRule a)
                (Rule.defaultToOriginal rewriteRule)
                nodeToRewrite
    in
    case top |> Result.map rewriteRule of
        Ok Nothing ->
            top

        Ok (Just result) ->
            result

        Err error ->
            Err error

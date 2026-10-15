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


module Morphir.Sample.Rules.RuleSet exposing (Category, Trade, ruleSet)

import Morphir.SDK.Rule as Rule exposing (Rule, any, anyOf, noneOf)
import String exposing (startsWith)


{-| The input to the rule set is usually represented with a record type where each field
corresponds to a fact in the fact set in traditional rule engine terms.
-}
type alias Trade =
    { side : Side
    , entityCode : String
    , account : String
    }


{-| The result of the rule set can be any type. In this case we simply enumerate the possible
classifications of a trade.
-}
type Category
    = StreetBorrow
    | BookBorrow
    | StreetLoan
    | BookLoan


{-| A rule set is represented as a list of partial functions. Each entry in the rule set is
created using the same helper function that turns the list of predicates into a single predicate
and also specifies the output of the rule. This provides an easy to read tabular format for
the rule set while still supporting very complex matching rules if needed.

Using the power of functional programming we can go beyond simple exact matches and apply more
complex matching rules such as `noneOf`, `anyOf` or `startsWith` directly in the decision table.

-}
ruleSet : Rule Trade Category
ruleSet =
    Rule.chain
        --      Side        Entity Code                     Account             Category
        [ rule Borrow (noneOf [ "12345", "23456" ]) (startsWith "00") StreetBorrow
        , rule Borrow any any BookBorrow
        , rule Loan (anyOf [ "00110", "22556" ]) any StreetLoan
        , rule Loan any any BookLoan
        ]


{-| Utility function that defines the specific behavior of rules. Inputs are chosen explicitly to
make rule definition easier and cleaner by using either a specific value to match against or a predicate
function for flexibility.
-}
rule : Side -> (String -> Bool) -> (String -> Bool) -> Category -> Trade -> Maybe Category
rule side matchEntityCode matchAccount category trade =
    if (side == trade.side) && matchEntityCode trade.entityCode && matchAccount trade.account then
        Just category

    else
        Nothing


{-| Utility type to describe which side the trade is on.
-}
type Side
    = Borrow
    | Loan

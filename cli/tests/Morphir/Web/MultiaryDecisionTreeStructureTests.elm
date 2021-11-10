module Morphir.Web.MultiaryDecisionTreeStructureTests exposing (..)

import Debug exposing (log)
import List exposing (length)
import Morphir.IR.Name as Name
import Morphir.IR.Type as Type
import Morphir.Visual.Components.MultiaryDecisionTree exposing (Node(..))

import Element exposing (none, paddingEach, row, text)
import Expect
import Html exposing (label, var)
import Morphir.IR.Literal exposing (Literal(..))
import Morphir.IR.Value as Value
import Morphir.Visual.Components.MultiaryDecisionTree exposing (Node(..))
import Morphir.Visual.ViewPattern as ViewPattern
import Morphir.Web.MultiaryDecisionTreeTest as MultiaryDecisionTreeTest exposing (..)
import Test exposing (..)

leaf =
  Leaf (Value.Variable ( 0, Type.Unit () ) [ "foo" ])

branch1 =
  Branch
  { subject = Value.Variable ( 0, Type.Unit () ) [ "foo" ]
      , subjectEvaluationResult = Nothing
      , branches =
         []
   }
branch2 =
         Branch
           { subject = Value.Variable ( 0, Type.Unit () ) [ "foo" ]
           , subjectEvaluationResult = Nothing
           , branches =
               [ ( Value.ConstructorPattern () ( [], [], [ "yes" ] ) [], leaf)
               , ( Value.WildcardPattern (), leaf )
               , ( Value.WildcardPattern (), leaf )
               ]
           }

--countLeaf : Test
--countLeaf  =
--     describe "Count Total Leaves Tests"
--        [
--            test "1 Leaf" <|
--            \_ -> MultiaryDecisionTreeTest.getLeaf leaf 0
--                    |> Expect.equal 1
--            ,test "3 Leaves" <|
--            \_ -> MultiaryDecisionTreeTest.getLeaf branch1 0
--                    |> Expect.equal 3
--        ]
countNodes : Test
countNodes  =
    describe "Count Nodes Tests"
                [
                   test "1 Node- A Leaf" <|
                    \_ ->
                        length( MultiaryDecisionTreeTest.viewNode 0 Nothing leaf)
                        |> Expect.equal 1
                   -- ,test "1 Node - A Branch " <|
                   --\_ ->
                   --     MultiaryDecisionTreeTest.getBranches branch1
                   --     |> log "number"
                   --     |> Expect.equal 1
                ]
countBranches : Test
countBranches  =
     describe "Count branches Tests"
                   [
                      test "1 Branch" <|
                      \_ ->
                            length( MultiaryDecisionTreeTest.viewNode 0 Nothing branch1)
                            |> Expect.equal 1

                       ,test "4 Branches" <|
                       \_ ->
                             length( MultiaryDecisionTreeTest.viewNode 0 Nothing branch2)
                             |> Expect.equal 4
                   ]


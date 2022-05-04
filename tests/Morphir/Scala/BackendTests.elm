module Morphir.Scala.BackendTests exposing (..)



import Expect
import Morphir.IR.FQName as FQName
import Morphir.IR.Name as Name
import Morphir.IR.Path as IRPath
import Morphir.IR.Type as IRType
import Morphir.Scala.AST as Scala
import Test exposing (Test, describe, test)
import Morphir.Scala.Backend as Backend


mapValueNameTests : Test
mapValueNameTests =
    let
        assert inList outString =
            test ("Genarated Scala name " ++ outString) <|
                \_ ->
                    Name.fromList inList
                        |> Backend.mapValueName
                        |> Expect.equal outString
    in
    describe "toScalaName"
        [ assert [ "full", "name" ] "fullName"
        , assert ["implicit"] "_implicit"
        ]



mapFQNameToPathAndNameTests : Test
mapFQNameToPathAndNameTests =
    let
        assert inFQName outTuple =
            test ("Generate Path and Name " ++ FQName.toString inFQName) <|
                \_ ->
                    inFQName
                        |> Backend.mapFQNameToPathAndName
                        |> Expect.equal outTuple
    in
    describe "toPathAndName"
        [ assert (FQName.fQName (IRPath.fromList[Name.fromList["Morphir"], Name.fromList["Reference"], Name.fromList["Model"]]) (IRPath.fromList[Name.fromList["Insight"]]) (Name.fromList["UseCase1"]))
            (["morphir", "reference", "model", "Insight"], ["UseCase1"])
        , assert (FQName.fQName (IRPath.fromList[Name.fromList["alpha"], Name.fromList["beta"], Name.fromList["gamma"]]) (IRPath.fromList[Name.fromList["omega"]]) (Name.fromList["phi"]))
            (["alpha", "beta", "gamma", "Omega"], ["phi"])
        ]


mapFQNameToTypeRefTests : Test
mapFQNameToTypeRefTests =
    let
        assert inFQName outTypeRef =
            test ("Generated Type Reference") <|
                \_ ->
                    inFQName
                        |> Backend.mapFQNameToTypeRef
                        |> Expect.equal outTypeRef
    in
    describe "toTypeRef"
        [
            assert (FQName.fQName (IRPath.fromList[Name.fromList["Morphir"], Name.fromList["Reference"], Name.fromList["Model"]]) (IRPath.fromList[Name.fromList["Insight"]]) (Name.fromList["UseCase1"]))
            (Scala.TypeRef ["morphir", "reference", "model", "Insight"] "UseCase1")
        ]


mapTypeTests : Test
mapTypeTests =
    let
        scalaType = (Backend.mapType (IRType.Variable () ["foo"]))
    in
    describe "Map Morphir IR Variable to Scala Type Variable"
        [ test "Map IR String to Scala String" <|
            \_  ->
            scalaType |> Expect.equal (Scala.TypeVar "Foo")
        ]




--mapTypeTest_Tuple : Test
--mapTypeTest_Tuple =
--    let
--        irTuple = IRType.Tuple [IRType.Variable "String", IRType.Variable "String"]
--    in


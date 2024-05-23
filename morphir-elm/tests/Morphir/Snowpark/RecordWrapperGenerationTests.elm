module Morphir.Snowpark.RecordWrapperGenerationTests exposing (..)

import Dict
import Expect
import Morphir.IR.AccessControlled exposing (public)
import Morphir.IR.Module exposing (emptyDefinition)
import Morphir.IR.Name as Name
import Morphir.IR.Path as Path
import Morphir.IR.Type as Type exposing (Type(..))
import Morphir.Scala.AST as Scala
import Morphir.Snowpark.MappingContext as MappingContext
import Morphir.Snowpark.RecordWrapperGenerator as RecordWrapperGenerator
import Set
import Test exposing (Test, describe, test)


stringTypeInstance : Type ()
stringTypeInstance =
    Reference () ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "string" ] ], [ "string" ] ) []


testDistributionName =
    Path.fromString "UTest"


typesDict =
    Dict.fromList
        [ -- A record with simple types
          ( Name.fromString "Emp1"
          , public
                { doc = ""
                , value =
                    Type.TypeAliasDefinition []
                        (Type.Record ()
                            [ { name = Name.fromString "firstname", tpe = stringTypeInstance }
                            , { name = Name.fromString "lastname", tpe = stringTypeInstance }
                            ]
                        )
                }
          )
        ]


testDistributionPackage =
    { modules =
        Dict.fromList
            [ ( Path.fromString "MyMod"
              , public { emptyDefinition | types = typesDict }
              )
            ]
    }


typeClassificationTests : Test
typeClassificationTests =
    let
        customizationOptions =
            { functionsToInline = Set.empty, functionsToCache = Set.empty }

        calculatedContext =
            MappingContext.processDistributionModules testDistributionName testDistributionPackage customizationOptions

        firstModule =
            Dict.get [ Name.fromString "MyMod" ] testDistributionPackage.modules |> Maybe.map (\access -> access.value)

        assertItCreatedWrapper =
            test "Wrapper creation" <|
                \_ ->
                    let
                        generationResult =
                            firstModule
                                |> Maybe.map (\mod -> RecordWrapperGenerator.generateRecordWrappers testDistributionName (Path.fromString "MyMod") calculatedContext mod.types)
                                |> Maybe.map (\scalaElementList -> scalaElementList |> List.map stringFromScalaTypeDefinition)
                                |> Maybe.withDefault []
                    in
                    Expect.equal [ "Trait:Emp1:2", "Object:Emp1:5", "Class:Emp1Wrapper:2" ] generationResult
    in
    describe "resolveTNam"
        [ assertItCreatedWrapper
        ]


stringFromScalaTypeDefinition : Scala.Documented (Scala.Annotated Scala.TypeDecl) -> String
stringFromScalaTypeDefinition scalaElement =
    case scalaElement.value.value of
        Scala.Object { name, members } ->
            "Object:" ++ name ++ ":" ++ (members |> List.length |> String.fromInt)

        Scala.Trait { name, members } ->
            "Trait:" ++ name ++ ":" ++ (members |> List.length |> String.fromInt)

        Scala.Class { name, members } ->
            "Class:" ++ name ++ ":" ++ (members |> List.length |> String.fromInt)

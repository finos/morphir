module Morphir.Elm.ExtractTypesTests exposing (tests)

import Dict
import Expect
import Morphir.Elm.ExtractTypes exposing (mapDistribution)
import Morphir.IR.AccessControlled exposing (public)
import Morphir.IR.Distribution exposing (Distribution(..))
import Morphir.IR.FQName exposing (fqn)
import Morphir.IR.Type as Type exposing (Type)
import Test exposing (Test, test)


tests : Test
tests =
    test "Extract types from sample"
        (\_ ->
            mapDistribution sampleDistro
                |> Expect.equal
                    []
        )


sampleDistro : Distribution
sampleDistro =
    Library
        [ [ "sample" ] ]
        Dict.empty
        { modules =
            Dict.fromList
                [ ( [ [ "sec", "lending" ] ]
                  , public
                        { types =
                            Dict.fromList
                                [ ( [ "borrow" ]
                                  , public
                                        { doc = ""
                                        , value =
                                            Type.TypeAliasDefinition []
                                                (Type.Record ()
                                                    [ Type.Field [ "rate" ] (Type.Reference () (fqn "Sample" "SecLending" "Rate") [])
                                                    ]
                                                )
                                        }
                                  )
                                ]
                        , values =
                            Dict.empty
                        }
                  )
                ]
        }
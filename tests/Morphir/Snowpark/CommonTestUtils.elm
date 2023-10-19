module Morphir.Snowpark.CommonTestUtils exposing (..)

import Dict exposing (Dict(..))
import Morphir.IR.Type as Type
import Morphir.IR.Name as Name
import Morphir.IR.Path as Path
import Morphir.IR.AccessControlled exposing (public)
import Morphir.IR.Module exposing (emptyDefinition)
import Morphir.IR.Name as Name


stringTypeInstance : Type.Type ()
stringTypeInstance = Type.Reference () ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "string" ] ], [ "string" ] ) []


testDistributionName : Path.Path
testDistributionName = (Path.fromString "UTest") 

typesDict = 
    Dict.fromList [
        -- A record with simple types
        (Name.fromString "Emp", 
        public { doc =  "", value = Type.TypeAliasDefinition [] (Type.Record () [
            { name = Name.fromString "firstname", tpe = stringTypeInstance },
            { name = Name.fromString "lastname", tpe = stringTypeInstance }
        ]) })
        , (Name.fromString "DeptKind", 
                 public { doc =  "", value = Type.CustomTypeDefinition [] (public (Dict.fromList [
                    (Name.fromString "Hr", [] ),
                    (Name.fromString "It", [] )
                 ])) }) 
    ]

testDistributionPackage = 
        ({ modules = Dict.fromList [
            ( Path.fromString "MyMod",
              public { emptyDefinition | types = typesDict } )
        ]}) 

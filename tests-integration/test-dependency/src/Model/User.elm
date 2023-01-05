module Model.User exposing (..)

import Morphir.Reference.Model.Formulas exposing (lawOfGravitation)
import Morphir.Reference.Model.Types exposing (FirstName, FooBarBazRecord, LastName, Mail)


type alias User =
    { firstName : FirstName
    , lastName : LastName
    , email : Mail
    }


userFirstName : User -> Mail
userFirstName user =
    user.email


calculateGravity : Float -> Float -> Float
calculateGravity f1 f2 =
    lawOfGravitation f1 f2

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


module Morphir.IR.SDK.Common exposing (..)

import Morphir.IR.Documented exposing (Documented)
import Morphir.IR.FQName as FQName exposing (FQName)
import Morphir.IR.Module exposing (ModuleName)
import Morphir.IR.Name as Name exposing (Name)
import Morphir.IR.Package exposing (PackageName)
import Morphir.IR.Path as Path
import Morphir.IR.QName as QName
import Morphir.IR.Type as Type exposing (Type)
import Morphir.IR.Value as Value exposing (Value)


packageName : PackageName
packageName =
    Path.fromString "Morphir.SDK"


toFQName : ModuleName -> String -> FQName
toFQName modulePath localName =
    localName
        |> Name.fromString
        |> QName.fromName modulePath
        |> FQName.fromQName packageName


binaryApply : ModuleName -> String -> va -> Value ta va -> Value ta va -> Value ta va
binaryApply moduleName localName attributes arg1 arg2 =
    Value.Apply attributes (Value.Apply attributes (Value.Reference attributes (toFQName moduleName localName)) arg1) arg2


tVar : String -> Type ()
tVar varName =
    Type.Variable () (Name.fromString varName)


tFun : List (Type ()) -> Type () -> Type ()
tFun argTypes returnType =
    let
        curry args =
            case args of
                [] ->
                    returnType

                firstArg :: restOfArgs ->
                    Type.Function () firstArg (curry restOfArgs)
    in
    curry argTypes


vSpec : String -> List ( String, Type () ) -> Type () -> ( Name, Documented (Value.Specification ()) )
vSpec name args returnType =
    ( Name.fromString name
    , Value.Specification
        (args
            |> List.map
                (\( argName, argType ) -> ( Name.fromString argName, argType ))
        )
        returnType
        |> Documented "documentation"
    )

module SlateX.DevBot.Scala.SlateXToScala.CoreTypes exposing (mapConstructor)

import SlateX.AST.Name exposing (Name)
import SlateX.AST.Path exposing (Path)
import SlateX.DevBot.Scala.AST as S
import SlateX.DevBot.Scala.SlateXToScala.Report as Report


mapConstructor : String -> String -> List S.Type -> S.Type
mapConstructor moduleName typeName scalaArgs =
    let
        scalaModule =
            case moduleName of
                "Basics" ->
                    if typeName == "Bool" then
                        "Bool"

                    else if typeName |> String.startsWith "Int" then
                        "Int"

                    else
                        moduleName

                _ ->
                    moduleName

        path =
            [ "morphir", "sdk", scalaModule ]

        name =
            typeName
    in
    case scalaArgs of
        [] ->
            S.TypeRef path name

        _ ->
            S.TypeApply
                (S.TypeRef path name)
                scalaArgs

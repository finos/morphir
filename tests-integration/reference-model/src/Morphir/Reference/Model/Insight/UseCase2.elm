module Morphir.Reference.Model.Insight.UseCase2 exposing (..)


getDepartmentCode : String -> String -> Maybe String -> Maybe String -> String
getDepartmentCode departmentCode departmentPlant departmentProcessName overDepartmentCode =
    case overDepartmentCode of
        Nothing ->
            departmentCode

        Just overDepCode ->
            case overDepCode of
                "1B2C" ->
                    case departmentProcessName of
                        Just "SCIENCE" ->
                            case departmentPlant of
                                "N" ->
                                    overDepCode

                                _ ->
                                    departmentCode

                        Nothing ->
                            departmentCode

                _ ->
                    overDepCode

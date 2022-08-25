module Morphir.Reference.Model.Relational exposing (..)

import Morphir.SDK.List as List


type alias JobPosting =
    { companyName : String
    , position : String
    }


type alias Company =
    { name : String
    , numberOfEmployees : Int
    }


innerJoin1 : List JobPosting -> List Company -> List { position : String, companySize : Int }
innerJoin1 jobPostings companies =
    jobPostings
        |> List.innerJoin companies
            (\jobPosting company ->
                jobPosting.companyName == company.name
            )
        |> List.map
            (\( jobPosting, company ) ->
                { position =
                    jobPosting.position
                , companySize =
                    company.numberOfEmployees
                }
            )


leftJoin1 : List JobPosting -> List Company -> List { position : String, companySize : Int }
leftJoin1 jobPostings companies =
    jobPostings
        |> List.leftJoin companies
            (\jobPosting company ->
                jobPosting.companyName == company.name
            )
        |> List.map
            (\( jobPosting, maybeCompany ) ->
                { position =
                    jobPosting.position
                , companySize =
                    maybeCompany
                        |> Maybe.map .numberOfEmployees
                        |> Maybe.withDefault 0
                }
            )

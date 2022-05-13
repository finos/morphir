module Morphir.Reference.Model.Sample.DataDefinition.Persistence.Expenditure exposing (..)

import Morphir.Reference.Model.Sample.DataDefinition.Persistence.Demand.Bills exposing (Bills)
import Morphir.Reference.Model.Sample.DataDefinition.Persistence.Demand.Loans exposing (Loans)


type Expenditure
    = Bills Bills
    | Loans Loans

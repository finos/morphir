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


module Morphir.Sample.Reg.LCR.Flows exposing (Amount, BusinessDate, Flow, ReportingEntity)

import Morphir.SDK.LocalDate exposing (LocalDate)
import Morphir.Sample.Reg.Currency exposing (Currency)
import Morphir.Sample.Reg.LCR.Basics exposing (..)
import Morphir.Sample.Reg.LCR.Counterparty exposing (CounterpartyId)
import Morphir.Sample.Reg.LCR.FedCodeRules exposing (RuleCode)
import Morphir.Sample.Reg.LCR.Product exposing (ProductId)


type alias BusinessDate =
    LocalDate


type alias ReportingEntity =
    Entity


type alias Amount =
    Float


type alias Flow =
    { amount : Amount
    , assetType : AssetCategoryCodes
    , businessDate : BusinessDate
    , collateralClass : AssetCategoryCodes
    , counterpartyId : CounterpartyId
    , currency : Currency
    , ruleCode : RuleCode
    , insured : InsuranceType
    , isTreasuryControl : Bool
    , isUnencumbered : Bool
    , maturityDate : BusinessDate
    , effectiveMaturityDate : BusinessDate
    , productId : ProductId
    }

{-
   Copyright 2020 Morgan Stanley

   Licensed under the Apache License, Version 2_0 (the "License");
   you may not use this file except in compliance with the License_
   You may obtain a copy of the License at

       http://www_apache_org/licenses/LICENSE-2_0

   Unless required by applicable law or agreed to in writing, software
   distributed under the License is distributed on an "AS IS" BASIS,
   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied_
   See the License for the specific language governing permissions and
   limitations under the License_
-}


module Morphir.Sample.Reg.LCR.FedCode exposing (..)

import Dict exposing (Dict)
import Morphir.Sample.Reg.Country as Country exposing (Country)
import Morphir.Sample.Reg.Currency as Currency exposing (Currency(..), country)
import Morphir.Sample.Reg.LCR.CentralBank exposing (CentralBank(..))


type alias PartyID =
    String


type alias CountryCode =
    String


type alias ProductType =
    String


type alias Description5G =
    String


type alias AdjustedAmountUSD =
    String


type alias AdjustedMXAmount =
    String


type alias Account =
    String


type alias CostCenterCode =
    String


type alias CostCenterDescription =
    String


type alias LegalEntityCode =
    String


type alias TenQLevel1 =
    String


type alias TenQLevel2 =
    String


type alias TenQLevel3 =
    String


type alias TenQLevel4 =
    String


type alias TenQLevel5 =
    String


type alias TenQLevel6 =
    String


type Money a
    = Money Float


type Usd
    = Usd


type Mx
    = Mx


type alias LegalEntity =
    { code : LegalEntityCode
    , country : Maybe Country
    }


type alias CostCenter =
    { code : CostCenterCode
    , description : CostCenterDescription
    }


type alias Counterparty =
    { country : Country
    , description5G : Description5G
    , account : Account
    }


type alias Cashflow =
    { legalEntity : LegalEntity
    , partyId : PartyID
    , currency : Currency
    , counterparty : Counterparty
    , amountUSD : Money Usd
    , amountMx : Money Mx
    , tenQLevel1 : TenQLevel1
    , tenQLevel2 : TenQLevel2
    , tenQLevel3 : TenQLevel3
    , tenQLevel4 : TenQLevel4
    , tenQLevel5 : TenQLevel5
    , tenQLevel6 : TenQLevel6
    }


type FedCode
    = IA31
    | IA32
    | IA33
    | IA34
    | IA35
    | IA36
    | IA37
    | IA38
    | IA39
    | IA41
    | IA42
    | IA43
    | IA44
    | IA45
    | IA46
    | IA47
    | IA48
    | IA49
    | IU1
    | IU2
    | IU4
    | OW9
    | OW10
    | Unclassified


type CentralBankSubProduct
    = FRB
    | SNB
    | BOE
    | ECB
    | BOJ
    | RBA
    | BOC
    | OCB
    | Other_Cash_Currency_And_Coin


centralBankToSubProduct : CentralBank -> CentralBankSubProduct
centralBankToSubProduct cb =
    case cb of
        Federal_Reserve_Bank ->
            FRB

        Swiss_National_Bank ->
            SNB

        Bank_of_England ->
            BOE

        European_Central_Bank ->
            ECB

        Bank_of_Japan ->
            BOJ

        Reserve_Bank_of_Australia ->
            RBA

        Bank_of_Canada ->
            BOC

        -- TODO What maps to Other Cash Currency and Coin????
        _ ->
            OCB


classify : Cashflow -> Dict PartyID CentralBank -> FedCode
classify cashflow centralBanks =
    let
        partyAsCentralBank : Maybe CentralBank
        partyAsCentralBank =
            Dict.get cashflow.partyId centralBanks
    in
    case partyAsCentralBank of
        -- It is a central bank
        Just centralBank ->
            if cashflow.tenQLevel6 /= "Segregated Cash" then
                case centralBankToSubProduct centralBank of
                    FRB ->
                        IA31

                    SNB ->
                        IA32

                    BOE ->
                        IA33

                    ECB ->
                        IA34

                    BOJ ->
                        IA35

                    RBA ->
                        IA36

                    BOC ->
                        IA37

                    OCB ->
                        IA38

                    Other_Cash_Currency_And_Coin ->
                        IA39

            else
                case centralBankToSubProduct centralBank of
                    FRB ->
                        IA41

                    SNB ->
                        IA42

                    BOE ->
                        IA43

                    ECB ->
                        IA44

                    BOJ ->
                        IA45

                    RBA ->
                        IA46

                    BOC ->
                        IA47

                    OCB ->
                        IA48

                    Other_Cash_Currency_And_Coin ->
                        IA49

        -- It is not a central bank
        Nothing ->
            --if List.member (String.toUpper cashflow.tenQLevel5) [ "CASH AND DUE FROM BANKS", "OVERNIGHT AND TERM DEPOSITS", "CASH EQUIVALENTS" ] then
            if String.toUpper cashflow.tenQLevel5 == "CASH AND DUE FROM BANKS" || String.toUpper cashflow.tenQLevel5 == "OVERNIGHT AND TERM DEPOSITS" || String.toUpper cashflow.tenQLevel5 == "CASH EQUIVALENTS" then
                if netCashUSD cashflow >= 0 then
                    if isOnshore cashflow then
                        IU1

                    else
                        IU2

                else
                    IU4

            else
                -- Probably replace with maybe
                Unclassified


isOnshore : Cashflow -> Bool
isOnshore cashflow =
    cashflow.legalEntity.country == Currency.country cashflow.currency && cashflow.legalEntity.country == Just cashflow.counterparty.country


netCashUSD : Cashflow -> Float
netCashUSD cashflow =
    case cashflow.amountUSD of
        Money amount ->
            amount

module Morphir.Decoration.Model.PrivacyControl exposing (..)

-- @docs Sensitivity


type Sensitivity
    = MNPI
    | PII
    | PI
    | SPI
    | NPI
    | Private_Information
    | PHI
    | RBC_High_Risk_Data

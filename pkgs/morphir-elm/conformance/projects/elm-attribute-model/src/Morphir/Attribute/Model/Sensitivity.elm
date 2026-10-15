module Morphir.Attribute.Model.Sensitivity exposing (..)

-- @docs Sensitivity

type Sensitivity = MNPI
    | PII
    | PI
    | SPI
    | NPI
    | Private_Information
    | PHI
    | RBC_High_Risk_Data
module Morphir.Reference.Model.Formulas exposing (..)


lawOfGravitation : Float -> Float -> Float
lawOfGravitation f1 f2 =
    (f1 + f2) * 10


lawOfGravitation2 : Float -> Float -> Float -> Float
lawOfGravitation2 f1 f2 f3 =
    (f1 + f2) / f3


lawOfGravitation19 : Float -> Float -> Float -> Float
lawOfGravitation19 f1 f2 f3 =
    f1 / f2 / f3


lawOfGravitation3 : Float -> Float -> Float -> Float
lawOfGravitation3 f1 f2 f3 =
    f1 + f2 / (f3 + 10) * 3


lawOfGravitation4 : Float -> Float -> Float -> Float -> Float
lawOfGravitation4 f1 f2 f3 f4 =
    f1 + f2 / f3 * f4


lawOfGravitation5 : Float -> Float -> Float -> Float -> Float -> Float
lawOfGravitation5 f1 f2 f3 f4 f5 =
    (f1 + f2) * f5 / f3 * f4


lawOfGravitation6 : Float -> Float -> Float -> Float -> Float -> Float -> Float -> Float
lawOfGravitation6 f1 f2 f3 f4 f5 f6 f7 =
    f1 * f2 * f5 * f6 / f3 * f4 + f7


lawOfGravitation7 : Float -> Float -> Float -> Float -> Float -> Float -> Float -> Float
lawOfGravitation7 f1 f2 f3 f4 f5 f6 f7 =
    f1 + f3 / f5 + f6 + f4 / f7


lawOfGravitation8 : Float -> Float -> Float -> Float -> Float -> Float -> Float -> Float
lawOfGravitation8 f1 f2 f3 f4 f5 f6 f7 =
    f1 + f2 * f5 + f6 + f3 / f4 + f7


lawOfGravitation9 : Float -> Float -> Float -> Float -> Float -> Float -> Float -> Float -> Float -> Float -> Float
lawOfGravitation9 f1 f2 f3 f4 f5 f6 f7 f8 f9 f10 =
    f1 + f2 * f5 + f6 + f3 / f4 + f7 + f8 + f9 + f10


lawOfGravitation10 : Float -> Float -> Float -> Float -> Float
lawOfGravitation10 g m1 m2 r =
    (g * m1 * m2) / (r * r)


lawOfGravitation11 : Float -> Float -> Float -> Float -> Float
lawOfGravitation11 g m1 m2 r =
    g * m1 * m2 * r / r


lawOfGravitation12 : Float -> Float -> Float -> Float -> Float
lawOfGravitation12 g m1 m2 r =
    g * m1 * m2 / r * r


lawOfGravitation13 : Float -> Float -> Float -> Float -> Float
lawOfGravitation13 g m1 m2 r =
    g - m1 + m2 - r


lawOfGravitation14 : Float -> Float -> Float -> Float -> Float -> Float -> Float -> Float -> Float
lawOfGravitation14 g m1 m2 r m3 m4 m5 m6 =
    g * m1 * (m2 + m3 + m4 + m5 * m6) / r * r


unemploymentRate : Float -> Float -> Float
unemploymentRate unemployed employed =
    unemployed / employed


amortization : Float -> Float -> Float -> Float -> Float
amortization p r n t =
    (p * r / n) / (1 - (1 + r / n) - n * t)


amortization2 : Float -> Float -> Float -> Float -> Float
amortization2 p r n t =
    (p + r / n) / (1 - (1 + r / n) - n * t)

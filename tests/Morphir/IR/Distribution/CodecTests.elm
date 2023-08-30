module Morphir.IR.Distribution.CodecTests exposing (..)

import Dict
import Expect
import Json.Decode as Decode
import Json.Encode as Encode
import Morphir.Compiler.Codec as CompilerCodec
import Morphir.IR.AccessControlled exposing (private, public)
import Morphir.IR.Distribution as Distribution exposing (Distribution)
import Morphir.IR.FormatVersion.Codec as DistributionCodec
import Morphir.IR.Documented exposing (Documented)
import Morphir.IR.FQName exposing (fQName)
import Morphir.IR.Package as Package
import Morphir.IR.Type as Type exposing (Type)
import Test exposing (Test, describe, test)


tests : Test
tests =
    describe "Codec tests"
        [ test "When IR is encoded and decoded it should return itself"
            (\_ ->
                sampleIR
                    |> DistributionCodec.encodeVersionedDistribution
                    |> Encode.encode 4
                    |> Decode.decodeString DistributionCodec.decodeVersionedDistribution
                    |> Expect.equal (Ok sampleIR)
            )
        , test "Sample JSON should decode into sample IR"
            (\_ ->
                sampleJSON
                    |> Decode.decodeString DistributionCodec.decodeVersionedDistribution
                    |> Expect.equal (Ok sampleIR)
            )
        ]


sampleIR : Distribution
sampleIR =
    let
        packageName =
            [ [ "sample" ] ]

        packageDef : Package.Definition () (Type ())
        packageDef =
            { modules =
                Dict.fromList
                    [ ( [ [ "module", "a" ] ]
                      , public
                            { types =
                                Dict.fromList
                                    [ ( [ "bar" ]
                                      , public
                                            (Documented ""
                                                (Type.TypeAliasDefinition []
                                                    (Type.Reference () (fQName packageName [ [ "a" ] ] [ "foo" ]) [])
                                                )
                                            )
                                      )
                                    , ( [ "foo" ]
                                      , public
                                            (Documented ""
                                                (Type.CustomTypeDefinition []
                                                    (public
                                                        (Dict.fromList
                                                            [ ( [ "foo" ]
                                                              , [ ( [ "arg", "1" ], Type.Reference () (fQName packageName [ [ "b" ] ] [ "bee" ]) [] )
                                                                ]
                                                              )
                                                            ]
                                                        )
                                                    )
                                                )
                                            )
                                      )
                                    , ( [ "rec" ]
                                      , public
                                            (Documented " It's a rec "
                                                (Type.TypeAliasDefinition []
                                                    (Type.Record ()
                                                        [ Type.Field [ "field", "1" ]
                                                            (Type.Reference () (fQName packageName [ [ "a" ] ] [ "foo" ]) [])
                                                        , Type.Field [ "field", "2" ]
                                                            (Type.Reference () (fQName packageName [ [ "a" ] ] [ "bar" ]) [])
                                                        ]
                                                    )
                                                )
                                            )
                                      )
                                    ]
                            , values =
                                Dict.empty
                            , doc = Nothing
                            }
                      )
                    , ( [ [ "module", "b" ] ]
                      , private
                            { types =
                                Dict.fromList
                                    [ ( [ "bee" ]
                                      , public
                                            (Documented " It's a bee "
                                                (Type.CustomTypeDefinition []
                                                    (public (Dict.fromList [ ( [ "bee" ], [] ) ]))
                                                )
                                            )
                                      )
                                    ]
                            , values =
                                Dict.empty
                            , doc = Nothing
                            }
                      )
                    ]
            }
    in
    Distribution.Library packageName Dict.empty packageDef


sampleJSON : String
sampleJSON =
    """{
          "formatVersion":1,
          "distribution":[
             "library",
             [
                [
                   "sample"
                ]
             ],
             [
                
             ],
             {
                "modules":[
                   {
                      "name":[
                         [
                            "module",
                            "a"
                         ]
                      ],
                      "def":[
                         "public",
                         {
                            "types":[
                               [
                                  [
                                     "bar"
                                  ],
                                  [
                                     "public",
                                     [
                                        "",
                                        [
                                           "type_alias_definition",
                                           [
                                              
                                           ],
                                           [
                                              "reference",
                                              {
                                                 
                                              },
                                              [
                                                 [
                                                    [
                                                       "sample"
                                                    ]
                                                 ],
                                                 [
                                                    [
                                                       "a"
                                                    ]
                                                 ],
                                                 [
                                                    "foo"
                                                 ]
                                              ],
                                              [
                                                 
                                              ]
                                           ]
                                        ]
                                     ]
                                  ]
                               ],
                               [
                                  [
                                     "foo"
                                  ],
                                  [
                                     "public",
                                     [
                                        "",
                                        [
                                           "custom_type_definition",
                                           [
                                              
                                           ],
                                           [
                                              "public",
                                              [
                                                 [
                                                    [
                                                       "foo"
                                                    ],
                                                    [
                                                       [
                                                          [
                                                             "arg",
                                                             "1"
                                                          ],
                                                          [
                                                             "reference",
                                                             {
                                                                
                                                             },
                                                             [
                                                                [
                                                                   [
                                                                      "sample"
                                                                   ]
                                                                ],
                                                                [
                                                                   [
                                                                      "b"
                                                                   ]
                                                                ],
                                                                [
                                                                   "bee"
                                                                ]
                                                             ],
                                                             [
                                                                
                                                             ]
                                                          ]
                                                       ]
                                                    ]
                                                 ]
                                              ]
                                           ]
                                        ]
                                     ]
                                  ]
                               ],
                               [
                                  [
                                     "rec"
                                  ],
                                  [
                                     "public",
                                     [
                                        " It's a rec ",
                                        [
                                           "type_alias_definition",
                                           [
                                              
                                           ],
                                           [
                                              "record",
                                              {
                                                 
                                              },
                                              [
                                                 [
                                                    [
                                                       "field",
                                                       "1"
                                                    ],
                                                    [
                                                       "reference",
                                                       {
                                                          
                                                       },
                                                       [
                                                          [
                                                             [
                                                                "sample"
                                                             ]
                                                          ],
                                                          [
                                                             [
                                                                "a"
                                                             ]
                                                          ],
                                                          [
                                                             "foo"
                                                          ]
                                                       ],
                                                       [
                                                          
                                                       ]
                                                    ]
                                                 ],
                                                 [
                                                    [
                                                       "field",
                                                       "2"
                                                    ],
                                                    [
                                                       "reference",
                                                       {
                                                          
                                                       },
                                                       [
                                                          [
                                                             [
                                                                "sample"
                                                             ]
                                                          ],
                                                          [
                                                             [
                                                                "a"
                                                             ]
                                                          ],
                                                          [
                                                             "bar"
                                                          ]
                                                       ],
                                                       [
                                                          
                                                       ]
                                                    ]
                                                 ]
                                              ]
                                           ]
                                        ]
                                     ]
                                  ]
                               ]
                            ],
                            "values":[
                               
                            ]
                         }
                      ]
                   },
                   {
                      "name":[
                         [
                            "module",
                            "b"
                         ]
                      ],
                      "def":[
                         "private",
                         {
                            "types":[
                               [
                                  [
                                     "bee"
                                  ],
                                  [
                                     "public",
                                     [
                                        " It's a bee ",
                                        [
                                           "custom_type_definition",
                                           [
                                              
                                           ],
                                           [
                                              "public",
                                              [
                                                 [
                                                    [
                                                       "bee"
                                                    ],
                                                    [
                                                       
                                                    ]
                                                 ]
                                              ]
                                           ]
                                        ]
                                     ]
                                  ]
                               ]
                            ],
                            "values":[
                               
                            ]
                         }
                      ]
                   }
                ]
             }
          ]
       }
    """

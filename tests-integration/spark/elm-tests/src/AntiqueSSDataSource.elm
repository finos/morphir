{-
   Copyright 2022 Morgan Stanley

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


module AntiqueSSDataSource exposing (..)

import Csv.Decode as Decode exposing (..)
import CsvUtils exposing (..)
import SparkTests.Types exposing (..)


csvData : String
csvData =
    """name,ageOfItem,product,report
item 3287,-1.0,Paintings,Report #1
item 896539,-1.0,Paintings,
item 3288,-1.0,Knife,Report #2
item 896540,-1.0,Knife,
item 3289,-1.0,Plates,Report #3
item 896541,-1.0,Plates,
item 3290,-1.0,Furniture,Report #4
item 896542,-1.0,Furniture,
item 3291,-1.0,HistoryWritings,Report #5
item 896543,-1.0,HistoryWritings,
item 3292,0.0,Paintings,Report #6
item 896544,0.0,Paintings,
item 3293,0.0,Knife,Report #7
item 896545,0.0,Knife,
item 3294,0.0,Plates,Report #8
item 896546,0.0,Plates,
item 3295,0.0,Furniture,Report #9
item 896547,0.0,Furniture,
item 3296,0.0,HistoryWritings,Report #10
item 896548,0.0,HistoryWritings,
item 3297,19.0,Paintings,Report #11
item 896549,19.0,Paintings,
item 3298,19.0,Knife,Report #12
item 896550,19.0,Knife,
item 3299,19.0,Plates,Report #13
item 896551,19.0,Plates,
item 3300,19.0,Furniture,Report #14
item 896552,19.0,Furniture,
item 3301,19.0,HistoryWritings,Report #15
item 896553,19.0,HistoryWritings,
item 3302,20.0,Paintings,Report #16
item 896554,20.0,Paintings,
item 3303,20.0,Knife,Report #17
item 896555,20.0,Knife,
item 3304,20.0,Plates,Report #18
item 896556,20.0,Plates,
item 3305,20.0,Furniture,Report #19
item 896557,20.0,Furniture,
item 3306,20.0,HistoryWritings,Report #20
item 896558,20.0,HistoryWritings,
item 3307,21.0,Paintings,Report #21
item 896559,21.0,Paintings,
item 3308,21.0,Knife,Report #22
item 896560,21.0,Knife,
item 3309,21.0,Plates,Report #23
item 896561,21.0,Plates,
item 3310,21.0,Furniture,Report #24
item 896562,21.0,Furniture,
item 3311,21.0,HistoryWritings,Report #25
item 896563,21.0,HistoryWritings,
item 3312,99.0,Paintings,Report #26
item 896564,99.0,Paintings,
item 3313,99.0,Knife,Report #27
item 896565,99.0,Knife,
item 3314,99.0,Plates,Report #28
item 896566,99.0,Plates,
item 3315,99.0,Furniture,Report #29
item 896567,99.0,Furniture,
item 3316,99.0,HistoryWritings,Report #30
item 896568,99.0,HistoryWritings,
item 3317,100.0,Paintings,Report #31
item 896569,100.0,Paintings,
item 3318,100.0,Knife,Report #32
item 896570,100.0,Knife,
item 3319,100.0,Plates,Report #33
item 896571,100.0,Plates,
item 3320,100.0,Furniture,Report #34
item 896572,100.0,Furniture,
item 3321,100.0,HistoryWritings,Report #35
item 896573,100.0,HistoryWritings,
item 3322,101.0,Paintings,Report #36
item 896574,101.0,Paintings,
item 3323,101.0,Knife,Report #37
item 896575,101.0,Knife,
item 3324,101.0,Plates,Report #38
item 896576,101.0,Plates,
item 3325,101.0,Furniture,Report #39
item 896577,101.0,Furniture,
item 3326,101.0,HistoryWritings,Report #40
item 896578,101.0,HistoryWritings,
"""


antiqueSSDataSource : Result Error (List AntiqueSubset)
antiqueSSDataSource =
    Decode.decodeCsv Decode.FieldNamesFromFirstRow antiqueSSDecoder csvData

module Morphir.SDK.StringTests

open Morphir.SDK.Testing
open Morphir.SDK
open Morphir.SDK.Maybe

let toInt (value: string) = int value

[<Tests>]
let tests =
    let combiningTests =
        describe
            "Combining Strings"
            [ testCase "cons"
              <| fun _ -> Expect.equal "The truth is out there" (String.cons 'T' "he truth is out there")
              testCase "uncons non-empty"
              <| fun _ -> Expect.equal (Just('a', "bc")) (String.uncons "abc")
              testCase "uncons empty" <| fun _ -> Expect.equal Nothing (String.uncons "")

              testCase "join spaces"
              <| fun _ -> Expect.equal "cat dog cow" (String.join " " [ "cat"; "dog"; "cow" ])
              testCase "join slashes"
              <| fun _ -> Expect.equal "home/steve/Desktop" (String.join "/" [ "home"; "steve"; "Desktop" ])
              testCase "join - make it Hawaiian"
              <| fun _ -> Expect.equal "Hawaiian" (String.join "a" [ "H"; "w"; "ii"; "n" ])
              testCase "join - animals"
              <| fun _ -> Expect.equal "cat dog cow" (String.join " " [ "cat"; "dog"; "cow" ])
              testCase "join - path"
              <| fun _ -> Expect.equal "home/evan/Desktop" (String.join "/" [ "home"; "evan"; "Desktop" ])

              testCase "length string" <| fun _ -> Expect.equal 4 (String.length "four")
              testCase "length null" <| fun _ -> Expect.equal 0 (String.length null)

              testCase "reverse"
              <| fun _ -> Expect.equal "stressed" (String.reverse "desserts")
              testCase "repeat"
              <| fun _ -> Expect.equal "EchoEchoEcho" (String.repeat 3 "Echo")
              testCase "replace"
              <| fun _ ->
                  Expect.equal "Moving the replacement" (String.replace "Replac" "Mov" "Replacing the replacement")
              testCase "append"
              <| fun _ -> Expect.equal "HelloWorld" (String.append "Hello" "World")
              testCase "split"
              <| fun _ -> Expect.equal [ "earth"; "quake" ] (String.split " " "earth quake")
              testCase "concat"
              <| fun _ -> Expect.equal "Coming together" (String.concat [ "Coming"; " "; "together" ])
              testCase "words"
              <| fun _ ->
                  Expect.equal [ "Breaks"; "up"; "all"; "the"; "words" ] (String.words "Breaks up all the words")
              testCase "lines"
              <| fun _ -> Expect.equal [ "New"; "Line" ] (String.lines "New\nLine")

              testCase "slice1"
              <| fun _ -> Expect.equal "on" (String.slice 7 9 "snakes on a plane!")
              testCase "slice2"
              <| fun _ -> Expect.equal "snakes" (String.slice 0 6 "snakes on a plane!")
              testCase "slice3"
              <| fun _ -> Expect.equal "snakes on a" (String.slice 0 -7 "snakes on a plane!")
              testCase "slice4"
              <| fun _ -> Expect.equal "plane" (String.slice -6 -1 "snakes on a plane!")

              testCase "left 0" <| fun _ -> Expect.equal "" (String.left 0 "Number")
              testCase "left" <| fun _ -> Expect.equal "Mu" (String.left 2 "Mulder")

              testCase "right 0" <| fun _ -> Expect.equal "" (String.right 0 "Right")
              testCase "right" <| fun _ -> Expect.equal "ly" (String.right 2 "Scully")

              testCase "dropLeft 0"
              <| fun _ -> Expect.equal "Something" (String.dropLeft 0 "Something")
              testCase "dropLeft" <| fun _ -> Expect.equal "one" (String.dropLeft 2 "Alone")

              testCase "dropRight 0"
              <| fun _ -> Expect.equal "Left" (String.dropRight 0 "Left")
              testCase "dropRight" <| fun _ -> Expect.equal "Dr" (String.dropRight 2 "Drop")

              testCase "contains1"
              <| fun _ -> Expect.equal true (String.contains "the" "theory")
              testCase "contains2"
              <| fun _ -> Expect.equal false (String.contains "hat" "theory")
              testCase "contains3"
              <| fun _ -> Expect.equal false (String.contains "THE" "theory")

              testCase "startsWith1"
              <| fun _ -> Expect.equal true (String.startsWith "the" "theory")
              testCase "startsWith2"
              <| fun _ -> Expect.equal false (String.startsWith "ory" "theory")

              testCase "endsWith1"
              <| fun _ -> Expect.equal false (String.endsWith "the" "theory")
              testCase "endsWith2"
              <| fun _ -> Expect.equal true (String.endsWith "ory" "theory")

              testCase "indexes i"
              <| fun _ -> Expect.equal [ 1; 4; 7; 10 ] (String.indexes "i" "Mississippi")
              testCase "indexes ss"
              <| fun _ -> Expect.equal [ 2; 5 ] (String.indexes "ss" "Mississippi")
              testCase "indexes none"
              <| fun _ -> Expect.equal [] (String.indexes "needle" "haystack")
              testCase "indices i"
              <| fun _ -> Expect.equal [ 1; 4; 7; 10 ] (String.indices "i" "Mississippi")

              testCase "toInt1" <| fun _ -> Expect.equal (Some 123) (String.toInt "123")
              testCase "toInt2" <| fun _ -> Expect.equal (Some -42) (String.toInt "-42")
              testCase "toInt3" <| fun _ -> Expect.equal None (String.toInt "0a")

              testCase "fromInt1" <| fun _ -> Expect.equal "123" (String.fromInt 123)
              testCase "fromInt2" <| fun _ -> Expect.equal "-42" (String.fromInt -42)

              testCase "toFloat1" <| fun _ -> Expect.equal (Some 123.0) (String.toFloat "123")
              testCase "toFloat2" <| fun _ -> Expect.equal (Some -42.0) (String.toFloat "-42")
              testCase "toFloat3" <| fun _ -> Expect.equal (Some 3.1) (String.toFloat "3.1")
              testCase "toFloat4" <| fun _ -> Expect.equal None (String.toFloat "31a")

              testCase "fromFloat1" <| fun _ -> Expect.equal "123" (String.fromFloat 123.0)
              testCase "fromFloat2" <| fun _ -> Expect.equal "-42" (String.fromFloat -42.0)
              testCase "fromFloat3" <| fun _ -> Expect.equal "3.1" (String.fromFloat 3.1)

              testCase "fromChar" <| fun _ -> Expect.equal "a" (String.fromChar 'a')

              testCase "toList"
              <| fun _ -> Expect.equal [ 'a'; 'b'; 'c' ] (String.toList "abc")
              testCase "fromList"
              <| fun _ -> Expect.equal "abc" (String.fromList [ 'a'; 'b'; 'c' ])

              testCase "toUpper" <| fun _ -> Expect.equal "SEYMOUR" (String.toUpper "seymour")
              testCase "toLower" <| fun _ -> Expect.equal "skinner" (String.toLower "SKINNER")

              testCase "pad1" <| fun _ -> Expect.equal "  1  " (String.pad 5 ' ' "1")
              testCase "pad2" <| fun _ -> Expect.equal "  11 " (String.pad 5 ' ' "11")
              testCase "pad3" <| fun _ -> Expect.equal " 121 " (String.pad 5 ' ' "121")

              testCase "padLeft1" <| fun _ -> Expect.equal "....1" (String.padLeft 5 '.' "1")
              testCase "padLeft2" <| fun _ -> Expect.equal "...11" (String.padLeft 5 '.' "11")
              testCase "padLeft3"
              <| fun _ -> Expect.equal "..121" (String.padLeft 5 '.' "121")

              testCase "padRight1"
              <| fun _ -> Expect.equal "1...." (String.padRight 5 '.' "1")
              testCase "padRight2"
              <| fun _ -> Expect.equal "11..." (String.padRight 5 '.' "11")
              testCase "padRight3"
              <| fun _ -> Expect.equal "121.." (String.padRight 5 '.' "121")

              testCase "trim" <| fun _ -> Expect.equal "hats" (String.trim "  hats  \n")
              testCase "trimLeft"
              <| fun _ -> Expect.equal "hats  \n" (String.trimLeft "  hats  \n")
              testCase "trimRight"
              <| fun _ -> Expect.equal "  hats" (String.trimRight "  hats  \n")

              testCase "map"
              <| fun _ -> Expect.equal "a.b.c" (String.map (fun c -> if c.Equals '/' then '.' else c) "a/b/c")

              testCase "filter1"
              <| fun _ -> Expect.equal "22" (String.filter System.Char.IsDigit "R2-D2")
              testCase "filter2"
              <| fun _ -> Expect.equal "-" (String.filter System.Char.IsPunctuation "R2-D2")

              testCase "foldl"
              <| fun _ -> Expect.equal "emit" (String.foldl String.cons "" "time")

              testCase "foldr"
              <| fun _ -> Expect.equal "time" (String.foldr String.cons "" "time")

              testCase "any1"
              <| fun _ -> Expect.equal true (String.any System.Char.IsDigit "90210")
              testCase "any2"
              <| fun _ -> Expect.equal true (String.any System.Char.IsDigit "R2-D2")
              testCase "any3"
              <| fun _ -> Expect.equal false (String.any System.Char.IsDigit "rose")

              testCase "all1"
              <| fun _ -> Expect.equal true (String.all System.Char.IsDigit "90210")
              testCase "all2"
              <| fun _ -> Expect.equal false (String.all System.Char.IsDigit "R2-D2")
              testCase "all3"
              <| fun _ -> Expect.equal false (String.all System.Char.IsDigit "rose")

              testCase "ofLength1"
              <| fun _ -> Expect.equal (Some(123)) (String.ofLength 3 toInt "123")
              testCase "ofLength2"
              <| fun _ -> Expect.equal None (String.ofLength 3 toInt "12")
              testCase "ofLength3"
              <| fun _ -> Expect.equal None (String.ofLength 3 toInt "1234")

              testCase "ofMaxLength1"
              <| fun _ -> Expect.equal (Some(123)) (String.ofMaxLength 3 toInt "123")
              testCase "ofMaxLength2"
              <| fun _ -> Expect.equal (Some(12)) (String.ofMaxLength 3 toInt "12")
              testCase "ofMaxLength3"
              <| fun _ -> Expect.equal None (String.ofMaxLength 3 toInt "1234") ]              

    describe "String" [ combiningTests ]

module XunitTests =
    open Xunit
    open FsUnit.Xunit

    [<Fact>]
    let ``String capitalize should change the first letter to uppercase`` () =
        let input = "hello"
        let expected = "Hello"
        let actual = Morphir.SDK.String.capitalize input
        actual |> should equal expected

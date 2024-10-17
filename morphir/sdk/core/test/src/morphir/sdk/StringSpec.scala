/*
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
 */

package morphir.sdk

import zio.test.Assertion._
import zio.test._
import morphir.testing.MorphirBaseSpec

object StringSpec extends MorphirBaseSpec {
  def spec = suite("StringSpec")(
    suite("String.isEmpty specs")(
      isEmptyTests(
        "Hello World" -> false,
        ""            -> true
      ): _*
    ),
    suite("String.length specs")(
      lengthTests(
        "Hello World" -> 11,
        ""            -> 0
      ): _*
    ),
    suite("String.reverse specs")(
      reverseTests(
        "Hello World" -> "dlroW olleH",
        ""            -> ""
      ): _*
    ),
    suite("String.repeat specs")(
      repeatTests(
        (3, "ha", "hahaha")
      ): _*
    ),
    suite("String.replace specs")(
      replaceTests(
        (".", "-", "Json.Decode.succeed", "Json-Decode-succeed"),
        (",", "/", "a,b,c,d,e", "a/b/c/d/e")
      ): _*
    ),
    suite("String.fromInt specs")(
      fromIntTests(
        1  -> "1",
        -1 -> "-1"
      ): _*
    ),
    suite("String.append specs")(
      appendTests(
        ("butter", "fly", "butterfly")
      ): _*
    ),
    suite("String.join specs")(
      joinTests(
        ("a", List("H", "w", "ii", "n"), "Hawaiian"),
        (" ", List("cat", "dog", "cow"), "cat dog cow"),
        ("/", List("home", "evan", "Desktop"), "home/evan/Desktop")
      ): _*
    )
  )

  def isEmptyTests(cases: (String.String, Basics.Bool)*) =
    cases.map { case (input, expected) =>
      test(
        s"Given a String: '$input' calling isEmpty should return '$expected'"
      ) {
        assert(String.isEmpty(input))(equalTo(expected))
      }
    }

  def lengthTests(cases: (String.String, Basics.Int)*) =
    cases.map { case (input, expected) =>
      test(
        s"Given a String: '$input' calling length should return '$expected'"
      ) {
        assert(String.length(input))(equalTo(expected))
      }
    }

  def reverseTests(cases: (String.String, String.String)*) =
    cases.map { case (input, expected) =>
      test(
        s"Given a String: '$input' calling reverse should return '$expected'"
      ) {
        assert(String.reverse(input))(equalTo(expected))
      }
    }

  def repeatTests(cases: (Basics.Int, String.String, String.String)*) =
    cases.map { case (inputInt, inputStr, expected) =>
      test(
        s"Given a String: '$inputStr' and an Int: '$inputInt' calling repeat should return '$expected'"
      ) {
        assert(String.repeat(inputInt, inputStr))(equalTo(expected))
      }
    }

  def replaceTests(
    cases: (String.String, String.String, String.String, String.String)*
  ) =
    cases.map { case (literal, replacement, target, expected) =>
      test(
        s"Given a String: '$target' calling replace should return '$expected'"
      ) {
        assert(String.replace(literal, replacement, target))(
          equalTo(expected)
        )
      }
    }

  def fromIntTests(cases: (Basics.Int, String.String)*) =
    cases.map { case (input, expected) =>
      test(
        s"Given an Int: '$input' calling fromInt should return '$expected'"
      ) {
        assert(String.fromInt(input))(equalTo(expected))
      }
    }

  def appendTests(cases: (String.String, String.String, String.String)*) =
    cases.map { case (first, second, expected) =>
      test(
        s"Given Strings: '$first' and '$second' calling append should return '$expected'"
      ) {
        assert(String.append(first)(second))(equalTo(expected))
      }
    }

  def concatTests(cases: (List[String.String], String.String)*) =
    cases.map { case (input, expected) =>
      test(
        s"Given a List[String]: '$input' calling concat should return '$expected'"
      ) {
        assert(String.concat(input))(equalTo(expected))
      }
    }

  def splitTests(cases: (String.String, String.String, List[String])*) =
    cases.map { case (sep, target, expected) =>
      test(
        s"Given Strings: '$target' and 'sep' calling split should return '$expected'"
      ) {
        assert(String.split(sep)(target))(equalTo(expected))
      }
    }

  def toIntTests(cases: (String.String, Maybe.Maybe[Basics.Int])*) =
    cases.map { case (input, expected) =>
      test(
        s"Given a String: '$input' calling toInt should return '$expected'"
      ) {
        assert(String.toInt(input))(equalTo(expected))
      }
    }

  def toUpperTests(cases: (String.String, String.String)*) =
    cases.map { case (input, expected) =>
      test(
        s"Given a String: '$input' calling toUpper should return '$expected'"
      ) {
        assert(String.toUpper(input))(equalTo(expected))
      }
    }

  def toLowerTests(cases: (String.String, String.String)*) =
    cases.map { case (input, expected) =>
      test(
        s"Given a String: '$input' calling toLower should return '$expected'"
      ) {
        assert(String.toLower(input))(equalTo(expected))
      }
    }

  def trimTests(cases: (String.String, String.String)*) =
    cases.map { case (input, expected) =>
      test(
        s"Given a String: '$input' calling trim should return '$expected'"
      ) {
        assert(String.trim(input))(equalTo(expected))
      }
    }

  def joinWithCharTests(cases: (Char.Char, List[String.String], String.String)*) =
    cases.map { case (sep, chunks, expected) =>
      test(
        s"Given a List[String]: '$chunks' calling join with a Char separator should return '$expected'"
      ) {
        assert(String.join(sep)(chunks))(equalTo(expected))
      }
    }

  def joinTests(cases: (String.String, List[String.String], String.String)*) =
    cases.map { case (sep, chunks, expected) =>
      test(
        s"Given a List[String]: '$chunks' calling join with a String separator should return '$expected'"
      ) {
        assert(String.join(sep)(chunks))(equalTo(expected))
      }
    }

  def wordsTests(cases: (String.String, List[String])*) =
    cases.map { case (input, expected) =>
      test(
        s"Given a String: '$input' calling words should return '$expected'"
      ) {
        assert(String.words(input))(equalTo(expected))
      }
    }

  def linesTests(cases: (String.String, List[String])*) =
    cases.map { case (input, expected) =>
      test(
        s"Given a String: '$input' calling lines should return '$expected'"
      ) {
        assert(String.lines(input))(equalTo(expected))
      }
    }

  def sliceTests(
    cases: (Basics.Int, Basics.Int, String.String, String.String)*
  ) =
    cases.map { case (start, end, string, expected) =>
      test(
        s"Given a String: '$string' and Ints: $start and $end calling slice should return '$expected'"
      ) {
        assert(String.slice(start)(end)(string))(equalTo(expected))
      }
    }

  def leftTests(cases: (Basics.Int, String.String, String.String)*) =
    cases.map { case (n, str, expected) =>
      test(
        s"Given a String: '$str' calling left should return '$expected'"
      ) {
        assert(String.left(n)(str))(equalTo(expected))
      }
    }

  def rightTests(cases: (Basics.Int, String.String, String.String)*) =
    cases.map { case (n, str, expected) =>
      test(
        s"Given a String: '$str' calling right should return '$expected'"
      ) {
        assert(String.right(n)(str))(equalTo(expected))
      }
    }

  def dropLeftTests(cases: (Basics.Int, String.String, String.String)*) =
    cases.map { case (n, str, expected) =>
      test(
        s"Given a String: '$str' calling dropLeft should return '$expected'"
      ) {
        assert(String.dropLeft(n)(str))(equalTo(expected))
      }
    }

  def dropRightTests(cases: (Basics.Int, String.String, String.String)*) =
    cases.map { case (n, str, expected) =>
      test(
        s"Given a String: '$str' calling dropRight should return '$expected'"
      ) {
        assert(String.dropRight(n)(str))(equalTo(expected))
      }
    }

  def containsTests(cases: (String.String, String.String, Basics.Bool)*) =
    cases.map { case (substring, str, expected) =>
      test(
        s"Given Strings: '$substring' and '$str' calling contains should return '$expected'"
      ) {
        assert(String.contains(substring)(str))(equalTo(expected))
      }
    }

  def startsWithTests(cases: (String.String, String.String, Basics.Bool)*) =
    cases.map { case (substring, str, expected) =>
      test(
        s"Given Strings: '$substring' and '$str' calling startsWith should return '$expected'"
      ) {
        assert(String.startsWith(substring)(str))(equalTo(expected))
      }
    }

  def endsWithTests(cases: (String.String, String.String, Basics.Bool)*) =
    cases.map { case (substring, str, expected) =>
      test(
        s"Given String: '$substring' and '$str' calling endsWith should return '$expected'"
      ) {
        assert(String.endsWith(substring)(str))(equalTo(expected))
      }
    }

  def indexesTests(cases: (String.String, String.String, List[Basics.Int])*) =
    cases.map { case (substring, str, expected) =>
      test(
        s"Given String: '$substring' and '$str' calling indexes should return '$expected'"
      ) {
        assert(String.indexes(substring)(str))(equalTo(expected))
      }
    }

  def toFloatTests(cases: (String.String, Maybe.Maybe[Basics.Float])*) =
    cases.map { case (input, expected) =>
      test(
        s"Given a String: '$input' calling toFloat should return '$expected'"
      ) {
        assert(String.toFloat(input))(equalTo(expected))
      }
    }

  def fromFloatTests(cases: (Basics.Float, String.String)*) =
    cases.map { case (input, expected) =>
      test(
        s"Given a Float: '$input' calling fromFloat should return '$expected'"
      ) {
        assert(String.fromFloat(input))(equalTo(expected))
      }
    }

  def fromCharTests(cases: (Char.Char, String.String)*) =
    cases.map { case (input, expected) =>
      test(
        s"Given a Char: '$input' calling fromChar should return '$expected'"
      ) {
        assert(String.fromChar(input))(equalTo(expected))
      }
    }

  def consTests(cases: (Char.Char, String.String, String.String)*) =
    cases.map { case (ch, str, expected) =>
      test(
        s"Given a String: '$str' calling cons should return '$expected'"
      ) {
        assert(String.cons(ch)(str))(equalTo(expected))
      }
    }

  def unconsTests(cases: (String.String, Maybe.Maybe[(Char.Char, String)])*) =
    cases.map { case (input, expected) =>
      test(
        s"Given a String: '$input' calling uncons should return '$expected'"
      ) {
        assert(String.uncons(input))(equalTo(expected))
      }
    }

  def toListTests(cases: (String.String, List[Char.Char])*) =
    cases.map { case (input, expected) =>
      test(
        s"Given a String: '$input' calling toList should return '$expected'"
      ) {
        assert(String.toList(input))(equalTo(expected))
      }
    }

  def padTests(cases: (Basics.Int, Char.Char, String.String, String.String)*) =
    cases.map { case (n, ch, str, expected) =>
      test(
        s"Given a String: '$str', a Char: '$ch', and Int: '$n' calling pad should return '$expected'"
      ) {
        assert(String.pad(n)(ch)(str))(equalTo(expected))
      }
    }

  def padLeftTests(
    cases: (Basics.Int, Char.Char, String.String, String.String)*
  ) =
    cases.map { case (n, ch, str, expected) =>
      test(
        s"Given a String: '$str', a Char: '$ch', and Int: '$n' calling pad should return '$expected'"
      ) {
        assert(String.padLeft(n)(ch)(str))(equalTo(expected))
      }
    }

  def padRightTests(
    cases: (Basics.Int, Char.Char, String.String, String.String)*
  ) =
    cases.map { case (n, ch, str, expected) =>
      test(
        s"Given a String: '$str', a Char: '$ch', and Int: '$n' calling pad should return '$expected'"
      ) {
        assert(String.padRight(n)(ch)(str))(equalTo(expected))
      }
    }

  def trimLeftTests(cases: (String.String, String.String)*) =
    cases.map { case (input, expected) =>
      test(
        s"Given a String: '$input' calling trimLeft should return '$expected'"
      ) {
        assert(String.trimLeft(input))(equalTo(expected))
      }
    }

  def trimRightTests(cases: (String.String, String.String)*) =
    cases.map { case (input, expected) =>
      test(
        s"Given a String: '$input' calling trimRight should return '$expected'"
      ) {
        assert(String.trimRight(input))(equalTo(expected))
      }
    }
}

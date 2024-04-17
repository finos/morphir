package morphir.rdf.nquads.internal
import parsley.Parsley.{many, some}
import parsley.character.{letter, hexDigit, oneOf}
import parsley.syntax.character.{charLift, stringLift}
import parsley.character

object lexer:
  /// Represents a LANGTAG in NQuads' EBNF grammar
  /// LANGTAG	::=	'@' [a-zA-Z]+ ('-' [a-zA-Z0-9]+)*
  val LANGTAG = {
    val asciiLowerChar = oneOf('a' to 'z')
    val asciiUpperChar = oneOf('A' to 'Z')
    val asciiChar = asciiLowerChar | asciiUpperChar
    val digit = oneOf('0' to '9')
    val start = '@' ~> some(asciiChar).map(_.mkString("@", "", ""))
    val tail =
      many('-' ~> some(asciiChar).map(_.mkString("-", "", "")))
        .foldLeft("")(_ + _)
    val langtag = (start <~> tail).map(_ + _)
    langtag
  }

  val EOL = character.endOfLine
  val UCHAR = {
    val uchar4 =
      ('\\' ~> 'u' ~> hexDigit <~> hexDigit <~> hexDigit <~> hexDigit).map {
        case ((((a, b)), c), d) => s"\\u${a}${b}${c}${d}"
      }
    val uchar8 =
      ('\\' ~> 'U' ~> hexDigit <~> hexDigit <~> hexDigit <~> hexDigit <~> hexDigit <~> hexDigit <~> hexDigit <~> hexDigit)
        .map { case (((((((((a, b)), c), d), e), f), g), h)) =>
          s"\\U${a}${b}${c}${d}${e}${f}${g}${h}"
        }
    uchar4 | uchar8
  }

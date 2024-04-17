package morphir.rdf.nquads.internal
import parsley.Parsley.{atomic, many, some}
import parsley.character.{endOfLine, letter, hexDigit, oneOf, stringOfSome}
import parsley.syntax.character.{charLift, stringLift}
import parsley.character
import parsley.expr.chain

object lexer:
  /// Represents a LANGTAG in NQuads' EBNF grammar
  /// LANGTAG	::=	'@' [a-zA-Z]+ ('-' [a-zA-Z0-9]+)*
  lazy val LANGTAG =
    val base = atomic('@' ~> some(ascii.letter).span)
    val tail =
      atomic(many('-' ~> some(ascii.alphaNumeric))).span
    val langtag = atomic((base <~> tail)).map(_ + _)
    langtag
  end LANGTAG

  lazy val EOL = character.endOfLine

  lazy val UCHAR = {
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

  object ascii:
    val lowercaseLetter = oneOf('a' to 'z')
    val uppercaseLetter = oneOf('A' to 'Z')
    val letter = lowercaseLetter | uppercaseLetter
    val digit = oneOf('0' to '9')
    val alphaNumeric = letter | digit
  end ascii
end lexer

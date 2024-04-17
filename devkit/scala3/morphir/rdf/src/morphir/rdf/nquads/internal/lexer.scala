package morphir.rdf.nquads.internal
import parsley.Parsley.{atomic, many, some}
import parsley.character.{endOfLine, letter, hexDigit, oneOf, stringOfSome}
import parsley.unicode.{char as uchar, oneOf as oneOfUnicode}
import parsley.syntax.character.{charLift, stringLift}
import parsley.expr.chain

object lexer:
  /// Represents a LANGTAG in NQuads' EBNF grammar
  /// LANGTAG	::=	'@' [a-zA-Z]+ ('-' [a-zA-Z0-9]+)*
  lazy val LANGTAG = '@' ~> LANGTAG_TEXT

  lazy val LANGTAG_TEXT =
    val base = some(ascii.letter).span
    val tail =
      atomic(many('-' ~> some(ascii.alphaNumeric))).span
    val langtag = atomic((base <~> tail)).map(_ + _)
    langtag

  lazy val EOL = endOfLine

  lazy val UCHAR = 
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
  end UCHAR 

  object ascii:
    val lowercaseLetter = oneOf('a' to 'z')
    val uppercaseLetter = oneOf('A' to 'Z')
    val letter = lowercaseLetter | uppercaseLetter
    val digit = oneOf('0' to '9')
    val alphaNumeric = letter | digit
  end ascii

  object unicode:
    import parsley.unicode.oneOf
    val lower = oneOf(0x0061 to 0x007A)
    val upper = oneOf(0x0041 to 0x005A)
    val letter = lower | upper
    val digit = oneOf(0x0030 to 0x0039)
    val alphaNumeric = lower | upper | digit
  end unicode
end lexer

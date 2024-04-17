package morphir.rdf.nquads.internal
import parsley.Parsley.{atomic, many, some}
import parsley.character.{endOfLine, letter, hexDigit, oneOf, stringOfSome}
import parsley.unicode.{char as uchar, oneOf as oneOfUnicode, noneOf as noneOfUnicode}
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
      ('\\' ~> 'u' ~> hexDigit <~> hexDigit <~> hexDigit <~> hexDigit).span
    val uchar8 =
      ('\\' ~> 'U' ~> hexDigit <~> hexDigit <~> hexDigit <~> hexDigit <~> hexDigit <~> hexDigit <~> hexDigit <~> hexDigit).span
    uchar4 | uchar8
  end UCHAR 

  lazy val ECHAR = '\\' 

  lazy val PN_CHARS_BASE =
    unicode.upper | unicode.letter | oneOfUnicode(0x00C0 to 0x00D6) | oneOfUnicode(0x00D8 to 0x00F6) | oneOfUnicode(0x00F8 to 0x02FF) | oneOfUnicode(0x0370 to 0x037D) | oneOfUnicode(0x037F to 0x1FFF) | oneOfUnicode(0x200C to 0x200D) | oneOfUnicode(0x2070 to 0x218F) | oneOfUnicode(0x2C00 to 0x2FEF) | oneOfUnicode(0x3001 to 0xD7FF) | oneOfUnicode(0xF900 to 0xFDCF) | oneOfUnicode(0xFDF0 to 0xFFFD) | oneOfUnicode(0x10000 to 0xEFFFF)

  lazy val PN_CHARS_U = PN_CHARS_BASE | unicode.underscore | unicode.colon

  lazy val PN_CHARS = PN_CHARS_U | unicode.minus | unicode.digit | unicode.middot | oneOfUnicode(0x0300 to 0x036F) | oneOfUnicode(0x203F to 0x2040)

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
    val underscore = uchar(0x005F)
    val colon = uchar(0x003A)
    val minus = uchar(0x002D)
    val middot = uchar(0x00B7)
  end unicode
end lexer

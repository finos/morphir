package morphir.rdf.nquads.internal
import parsley.Parsley.{atomic, many, some}
import parsley.character.{endOfLine, letter, hexDigit, oneOf, stringOfSome}
import parsley.unicode.{
  char as uchar,
  oneOf as oneOfUnicode,
  noneOf as noneOfUnicode
}
import parsley.syntax.character.{charLift, stringLift}
import parsley.expr.chain
import morphir.rdf.nquads.internal.lexer.unicode.doubleQuote

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

  /// Represents an IRIREF in NQuads' EBNF grammar
  /// `IRIREF	::=	'<' ([^#x00-#x20<>"{}|^`\] | UCHAR)* '>'`
  lazy val IRIREF =
    val lessThan = 0x003c
    val greaterThan = 0x003e
    val doubleQuote = 0x0022
    val leftBracket = 0x007b
    val rightBracket = 0x007d
    val pipe = 0x007c
    val hat = 0x005e
    val grave = 0x0060
    val backslash = 0x005c
    val notAllowedSet = Set.from(0x00 to 0x20) ++ Set(
      lessThan,
      greaterThan,
      doubleQuote,
      leftBracket,
      rightBracket,
      pipe,
      hat,
      grave,
      backslash
    )
    val notAllowed = noneOfUnicode(notAllowedSet).span
    '<' ~> many((notAllowed | UCHAR)).span <~ '>'
  end IRIREF

  /// STRING_LITERAL_QUOTE	::=	'"' ([^#x22#x5C#xA#xD] | ECHAR | UCHAR)* '"'
  lazy val STRING_LITERAL_QUOTE =
    val doubleQuote = 0x0022
    val backslash = 0x005c
    val lf = 0x000a
    val cr = 0x000d

    val notAllowed = noneOfUnicode(doubleQuote, backslash, lf, cr)
    val string = many(notAllowed | ECHAR | UCHAR).span
    '"' ~> string <~ '"'

  lazy val UCHAR =
    val uchar4 =
      ('\\' ~> 'u' ~> hexDigit <~> hexDigit <~> hexDigit <~> hexDigit).span
    val uchar8 =
      ('\\' ~> 'U' ~> hexDigit <~> hexDigit <~> hexDigit <~> hexDigit <~> hexDigit <~> hexDigit <~> hexDigit <~> hexDigit).span
    uchar4 | uchar8
  end UCHAR

  lazy val ECHAR = '\\'

  lazy val PN_CHARS_BASE =
    unicode.upper | unicode.letter | oneOfUnicode(
      0x00c0 to 0x00d6
    ) | oneOfUnicode(0x00d8 to 0x00f6) | oneOfUnicode(
      0x00f8 to 0x02ff
    ) | oneOfUnicode(0x0370 to 0x037d) | oneOfUnicode(
      0x037f to 0x1fff
    ) | oneOfUnicode(0x200c to 0x200d) | oneOfUnicode(
      0x2070 to 0x218f
    ) | oneOfUnicode(0x2c00 to 0x2fef) | oneOfUnicode(
      0x3001 to 0xd7ff
    ) | oneOfUnicode(0xf900 to 0xfdcf) | oneOfUnicode(
      0xfdf0 to 0xfffd
    ) | oneOfUnicode(0x10000 to 0xeffff)

  lazy val PN_CHARS_U = PN_CHARS_BASE | unicode.underscore | unicode.colon

  lazy val PN_CHARS =
    PN_CHARS_U | unicode.minus | unicode.digit | unicode.middot | oneOfUnicode(
      0x0300 to 0x036f
    ) | oneOfUnicode(0x203f to 0x2040)

  object ascii:
    val lowercaseLetter = oneOf('a' to 'z')
    val uppercaseLetter = oneOf('A' to 'Z')
    val letter = lowercaseLetter | uppercaseLetter
    val digit = oneOf('0' to '9')
    val alphaNumeric = letter | digit
  end ascii

  object unicode:
    import parsley.unicode.oneOf
    val doubleQuote = uchar(0x0022)
    val lessThan = uchar(0x003c)
    val greaterThan = uchar(0x003e)
    val lower = oneOf(0x0061 to 0x007a)
    val upper = oneOf(0x0041 to 0x005a)
    val letter = lower | upper
    val digit = oneOf(0x0030 to 0x0039)
    val alphaNumeric = lower | upper | digit
    val underscore = uchar(0x005f)
    val colon = uchar(0x003a)
    val minus = uchar(0x002d)
    val middot = uchar(0x00b7)
  end unicode
end lexer

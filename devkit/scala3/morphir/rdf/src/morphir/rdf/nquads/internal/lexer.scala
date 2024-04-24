package morphir.rdf.nquads.internal
import parsley.Parsley
import parsley.Parsley.{atomic, eof, lookAhead, many, notFollowedBy, some}
import parsley.character.{letter, hexDigit, oneOf, stringOfSome}
import parsley.combinator.{manyTill, option, sepBy}
import parsley.errors.combinator.*
import parsley.unicode.{
  char as uchar,
  endOfLine,
  oneOf as oneOfUnicode,
  noneOf as noneOfUnicode,
  space
}
import parsley.syntax.character.{charLift, stringLift}
import parsley.expr.chain
import morphir.rdf.nquads.internal.lexer.unicode.doubleQuote

object tokens:
  enum CharacterToken:
    case UnicodeChar(ch: Int)
    case EOF
    case EOL
    case PERIOD
end tokens

object lexer:
  import tokens.CharacterToken
  import parsley.token.{Lexer, predicate}
  import parsley.token.descriptions.{LexicalDesc, NameDesc, SpaceDesc}

  private val desc = LexicalDesc.plain.copy(
    nameDesc = NameDesc.plain,
    spaceDesc = SpaceDesc(
      commentStart = "",
      commentEnd = "",
      commentLine = "#",
      commentLineAllowsEOF = true,
      nestedComments = false,
      space = predicate.Unicode(isWhitespace),
      whitespaceIsContextDependent = false
    )
  )
  private val lexer = Lexer(desc)
  def fully[A](p: Parsley[A]) = lexer.fully(p)

  /// Represents a LANGTAG in NQuads' EBNF grammar
  /// LANGTAG	::=	'@' [a-zA-Z]+ ('-' [a-zA-Z0-9]+)*
  lazy val LANGTAG = '@' ~> LANGTAG_TEXT

  lazy val LANGTAG_TEXT =
    val base = some(ascii.letter).span
    val tail =
      atomic(many('-' ~> some(ascii.alphaNumeric))).span
    lexer.lexeme((base <~> tail).map(_ + _))

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
    lexer.lexeme('<' ~> many((notAllowed | UCHAR)).span <~ '>')
  end IRIREF

  /// STRING_LITERAL_QUOTE	::=	'"' ([^#x22#x5C#xA#xD] | ECHAR | UCHAR)* '"'
  lazy val STRING_LITERAL_QUOTE =
    val doubleQuote = 0x0022
    val backslash = 0x005c
    val lf = 0x000a
    val cr = 0x000d

    val notAllowed = noneOfUnicode(doubleQuote, backslash, lf, cr)
    val string = many(UCHAR | ECHAR | notAllowed).span
    lexer.lexeme('"' ~> string <~ '"')

  lazy val BLANK_NODE_LABEL =
    lexer.lexeme("_:" ~> PN_LOCAL)

  lazy val UCHAR =
    val uchar4 =
      ('\\' ~> 'u' ~> hexDigit <~> hexDigit <~> hexDigit <~> hexDigit).span
    val uchar8 =
      ('\\' ~> 'U' ~> hexDigit <~> hexDigit <~> hexDigit <~> hexDigit <~> hexDigit <~> hexDigit <~> hexDigit <~> hexDigit).span
    atomic(uchar4 | uchar8)
  end UCHAR

  lazy val ECHAR =
    val backslash = 0x005c
    atomic(uchar(backslash) ~> oneOf('t', 'b', 'n', 'r', 'f', '"', '\'', '\\'))

  // TODO: This is SLOOOOW look to change to more efficient implementation (perhaps using functions)
  lazy val PN_LOCAL =
    val contentChars = characterSets.pnChars ++ characterSets.period
    val initialChar = oneOfUnicode(
      characterSets.pnCharsU ++ characterSets.digit
    ).void.label("PN_CHARS_U | [0-9]")
    val content =
      oneOfUnicode(characterSets.pnChars ++ characterSets.period).void
        .label("PN_CHARS | '.'")
    val trailingChars =
      sepBy(some(PN_CHARS).void.label("PN_CHARS"), some(PERIOD).void).void
    (initialChar <~> trailingChars).span

  // PN_CHARS_BASE	::=	[A-Z] | [a-z] | [#x00C0-#x00D6] | [#x00D8-#x00F6] | [#x00F8-#x02FF] | [#x0370-#x037D] | [#x037F-#x1FFF] | [#x200C-#x200D] | [#x2070-#x218F] | [#x2C00-#x2FEF] | [#x3001-#xD7FF] | [#xF900-#xFDCF] | [#xFDF0-#xFFFD] | [#x10000-#xEFFFF]
  lazy val PN_CHARS_BASE = oneOfUnicode(characterSets.pnCharsBase)
  lazy val PN_CHARS_U = oneOfUnicode(characterSets.pnCharsU)
  lazy val PN_CHARS = oneOfUnicode(characterSets.pnChars)

  lazy val PERIOD = parsley.unicode.char(0x002e)
  lazy val TAG_PREFIX = "^^"

  def isWhitespace(c: Int): Boolean = c match
    case 0x0020 | 0x0009 => true
    case _               => false

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

  object characterSets:
    lazy val lowerAsciiLetter = Set.from(0x0061 to 0x007a)
    lazy val upperAsciiLetter = Set.from(0x0041 to 0x005a)
    lazy val asciiLetter = lowerAsciiLetter ++ upperAsciiLetter
    lazy val digit = Set.from(0x0030 to 0x0039)
    lazy val underscore = Set(0x005f)
    lazy val minus = Set(0x002d)
    lazy val colon = Set(0x003a)
    lazy val period = Set(0x002e)
    lazy val pnCharsBaseAllowedUnicode =
      ((0x00c0 to 0x00d6) ++
        (0x00d8 to 0x00f6) ++
        (0x00f8 to 0x02ff) ++
        (0x0370 to 0x037d) ++
        (0x037f to 0x1fff) ++
        (0x200c to 0x200d) ++
        (0x2070 to 0x218f) ++
        (0x2c00 to 0x2fef) ++
        (0x3001 to 0xd7ff) ++
        (0xf900 to 0xfdcf) ++
        (0xfdf0 to 0xfffd) ++
        (0x10000 to 0xeffff)).toSet
    lazy val pnCharsBase = asciiLetter ++ pnCharsBaseAllowedUnicode
    lazy val pnCharsU = pnCharsBase ++ underscore ++ colon
    lazy val pnChars = pnCharsU ++ minus ++ digit ++ Set(0x00b7) ++ Set.from(
      (0x0300 to 0x036f) ++ (0x203f to 0x2040)
    )

  end characterSets
end lexer

object parser:
  import parsley.Parsley
  import parsley.combinator.option
  lazy val nquadsDoc = sepBy(statement, endOfLine)
  lazy val statement =
    subject <~> predicate <~> object$ <~> option(graphLabel) <~> lexer.PERIOD
  lazy val subject = lexer.IRIREF | lexer.BLANK_NODE_LABEL
  lazy val predicate = lexer.IRIREF
  lazy val object$ = lexer.IRIREF | lexer.BLANK_NODE_LABEL | literal
  lazy val graphLabel = lexer.IRIREF | lexer.BLANK_NODE_LABEL
  lazy val literalForm = lexer.STRING_LITERAL_QUOTE
  lazy val literal =
    literalForm ~> ("^^" ~> (lexer.IRIREF | lexer.LANGTAG)) | literalForm
end parser

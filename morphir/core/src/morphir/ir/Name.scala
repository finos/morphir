package morphir.ir

import kyo.Chunk
import io.github.iltotore.iron.*
import io.github.iltotore.iron.constraint.string.*

import scala.util.matching.Regex
import Name.Token

/** Name is a union of ClassicName (pre-v4 semantics) and CanonicalName (v4 semantics).
  *
  * Represents human-readable identifiers made up of words, allowing the same identifiers
  * to work across various naming conventions. Abbreviations are stored as individual
  * single-letter words (e.g. "USD" → `["u","s","d"]`) and coalesced for display.
  *
  * Use `Name.fold` to handle the two variants.
  *
  * API aligned with morphir-elm's `Morphir.IR.Name`: `fromList`, `toList`, `fromString`,
  * `toTitleCase`, `toCamelCase`, `toSnakeCase`, `toHumanWords`, `toHumanWordsTitle`.
  */
sealed trait Name:
  def tokens: Chunk[Token]
  def toCanonicalString: String

  /** Convert name to list of segment strings (morphir-elm `Name.toList`).
    *
    * {{{
    * Name.fromStringClassic("fooBar_baz 123").toList // List("foo", "bar", "baz", "123")
    * Name.fromStringClassic("valueInUSD").toList     // List("value", "in", "u", "s", "d")
    * }}}
    */
  def toList: List[String] =
    tokens.toSeq.map(Token.value).toList

  /** Title-case string (morphir-elm `Name.toTitleCase`).
    *
    * Each word is capitalized and concatenated. Single-letter words from
    * abbreviations naturally form upper-case runs.
    *
    * {{{
    * Name.fromList(List("foo", "bar", "baz", "123")).toTitleCase   // "FooBarBaz123"
    * Name.fromList(List("value", "in", "u", "s", "d")).toTitleCase // "ValueInUSD"
    * }}}
    */
  def toTitleCase: String =
    toList.map(Name.capitalize).mkString

  /** Camel-case string (morphir-elm `Name.toCamelCase`).
    *
    * Like title-case but the first word stays lowercase.
    *
    * {{{
    * Name.fromList(List("foo", "bar", "baz", "123")).toCamelCase   // "fooBarBaz123"
    * Name.fromList(List("value", "in", "u", "s", "d")).toCamelCase // "valueInUSD"
    * }}}
    */
  def toCamelCase: String =
    toList match
      case Nil       => ""
      case h :: tail => (h :: tail.map(Name.capitalize)).mkString

  /** Snake-case string (morphir-elm `Name.toSnakeCase`).
    *
    * Words joined with underscores. Consecutive single-letter words (abbreviations)
    * are coalesced into one upper-case word.
    *
    * {{{
    * Name.fromList(List("foo", "bar", "baz", "123")).toSnakeCase   // "foo_bar_baz_123"
    * Name.fromList(List("value", "in", "u", "s", "d")).toSnakeCase // "value_in_USD"
    * }}}
    */
  def toSnakeCase: String =
    toHumanWords.mkString("_")

  /** Human-readable words (morphir-elm `Name.toHumanWords`).
    *
    * Like `toList` but consecutive single-letter words are coalesced into
    * one upper-case abbreviation.
    *
    * {{{
    * Name.fromList(List("value", "in", "u", "s", "d")).toHumanWords // List("value", "in", "USD")
    * Name.fromList(List("foo", "bar", "baz", "123")).toHumanWords   // List("foo", "bar", "baz", "123")
    * }}}
    */
  def toHumanWords: List[String] =
    Name.toHumanWordsFromList(toList)

  /** Human-readable words with first word capitalized (morphir-elm `Name.toHumanWordsTitle`).
    *
    * {{{
    * Name.fromList(List("value", "in", "u", "s", "d")).toHumanWordsTitle // List("Value", "in", "USD")
    * }}}
    */
  def toHumanWordsTitle: List[String] =
    toHumanWords match
      case first :: rest => Name.capitalize(first) :: rest
      case Nil           => Nil

object Name:

  private def capitalize(s: String): String =
    s.headOption.fold(s)(h => h.toUpper + s.drop(1))

  /** Coalesce single-letter runs into one upper-case word (morphir-elm toHumanWords logic). */
  private def toHumanWordsFromList(words: List[String]): List[String] =
    def join(abbrev: List[String]): String =
      abbrev.mkString.toUpperCase
    def process(prefix: List[String], abbrev: List[String], suffix: List[String]): List[String] =
      suffix match
        case Nil =>
          if abbrev.isEmpty then prefix else prefix ::: List(join(abbrev))
        case first :: rest =>
          if first.length == 1 then
            process(prefix, abbrev :+ first, rest)
          else
            abbrev match
              case Nil =>
                process(prefix :+ first, Nil, rest)
              case _ =>
                process(prefix :+ join(abbrev) :+ first, Nil, rest)
    words match
      case one :: Nil if one.length == 1 => words
      case _                              => process(Nil, Nil, words)

  /** Build a name from a list of words (morphir-elm `Name.fromList`); produces ClassicName.
    *
    * {{{
    * Name.fromList(List("value", "in", "u", "s", "d")).toTitleCase // "ValueInUSD"
    * }}}
    */
  def fromList(words: List[String]): Name =
    ClassicName(Chunk(words.flatMap(s => word(s.toLowerCase)).toList*))

  /** Build CanonicalName from list of words (each segment as Word token). */
  private[ir] def fromListAsCanonical(words: List[String]): CanonicalName =
    CanonicalName(Chunk(words.flatMap(s => word(s.toLowerCase)).toList*))

  // ---------------------------------------------------------------------------
  // Iron constraints for Token payloads (v4: words = [a-z0-9]+, acronyms = [A-Z0-9]+)
  // ---------------------------------------------------------------------------
  private type ValidWord = Match["^[a-z0-9]+$"]
  private type ValidAcronym = Match["^[A-Z0-9]+$"]

  // ---------------------------------------------------------------------------
  // Token: Word | Acronym (only constructible via Name parsers)
  // ---------------------------------------------------------------------------
  sealed trait Token
  object Token:
    private[Name] case class Word(value: String :| ValidWord) extends Name.Token
    private[Name] case class Acronym(value: String :| ValidAcronym) extends Name.Token

    def value(t: Name.Token): String = t match
      case w: Word    => w.value
      case a: Acronym => a.value

    extension (t: Name.Token)
      def isWord: Boolean = t match
        case _: Word    => true
        case _: Acronym => false
      def isAcronym: Boolean = t match
        case _: Word    => false
        case _: Acronym => true
      def fold[A](onWord: String => A, onAcronym: String => A): A =
        val s = value(t)
        t match
          case _: Word    => onWord(s)
          case _: Acronym => onAcronym(s)

  // ---------------------------------------------------------------------------
  // Private construction (only Name parsers use these)
  // ---------------------------------------------------------------------------
  private[ir] def word(s: String): Option[Name.Token] =
    s.refineOption[ValidWord].map(Token.Word.apply)

  private[ir] def acronym(s: String): Option[Name.Token] =
    s.refineOption[ValidAcronym].map(Token.Acronym.apply)

  // Classic parsing: morphir-elm behaviour — regex to only accept, one Word per segment
  private val classicWordPattern: Regex = """([a-zA-Z][a-z]*|[0-9]+)""".r
  private val canonicalPattern: Regex = """^([a-z0-9]+|\([a-z0-9]+\))(-([a-z0-9]+|\([a-z0-9]+\)))*$""".r

  /** Returns ClassicName directly for use by morphir-classic and tests. */
  def classicName(input: String): ClassicName =
    val segments = classicWordPattern.findAllIn(input).matchData.map(_.matched.toLowerCase).toList
    val toks = segments.flatMap(word).toList
    ClassicName(Chunk(toks*))

  /** Parse with classic (morphir-elm) rules; returns ClassicName as Name.
    *
    * {{{
    * Name.fromStringClassic("fooBar_baz 123").toList // List("foo", "bar", "baz", "123")
    * Name.fromStringClassic("valueInUSD").toList     // List("value", "in", "u", "s", "d")
    * Name.fromStringClassic("_-%").toList            // List()
    * }}}
    */
  def fromStringClassic(input: String): Name =
    classicName(input)

  /** Smart parser: tries v4 canonical format first, falls back to classic with acronym coalescence.
    *
    * {{{
    * Name.fromString("value-in-(usd)") // CanonicalName with explicit acronym
    * Name.fromString("valueInUSD")     // CanonicalName with coalesced "USD" acronym
    * }}}
    */
  def fromString(input: String): Name =
    parseCanonical(input).getOrElse {
      val segments = classicWordPattern.findAllIn(input).matchData.map(_.matched.toLowerCase).toList
      val toks = coalesceToTokens(segments)
      CanonicalName(Chunk(toks*))
    }

  private def parseCanonical(input: String): Option[Name] =
    input match
      case canonicalPattern(_*) =>
        val toks = input.split('-').toList.flatMap {
          case s if s.startsWith("(") && s.endsWith(")") && s.length > 2 =>
            acronym(s.substring(1, s.length - 1).toUpperCase).toList
          case s =>
            word(s).toList
        }
        Some(CanonicalName(Chunk(toks*)))
      case _ =>
        None

  private def coalesceToTokens(segments: List[String]): List[Name.Token] =
    def flushAcronym(singleLetterBuf: List[String], acc: List[Name.Token]): List[Name.Token] =
      if singleLetterBuf.nonEmpty then
        acronym(singleLetterBuf.reverse.mkString.toUpperCase).toList ::: acc
      else acc

    def go(rest: List[String], singleLetterBuf: List[String], acc: List[Name.Token]): List[Name.Token] =
      rest match
        case Nil =>
          val withAcronym = flushAcronym(singleLetterBuf, acc)
          withAcronym.reverse
        case h :: t =>
          if h.length == 1 then
            go(t, h :: singleLetterBuf, acc)
          else
            val withAcronym = flushAcronym(singleLetterBuf, acc)
            word(h) match
              case Some(w) => go(t, Nil, w :: withAcronym)
              case None   => go(t, singleLetterBuf, withAcronym)
    go(segments, Nil, Nil)

  def fold[A](name: Name)(onClassic: ClassicName => A, onCanonical: CanonicalName => A): A =
    name match
      case c: ClassicName    => onClassic(c)
      case c: CanonicalName  => onCanonical(c)

  def apply(input: String): Name = fromString(input)
end Name

final case class ClassicName private[ir] (tokens: Chunk[Token]) extends Name:
  def toCanonicalString: String =
    tokens.toSeq.map(Token.value).mkString("-")

end ClassicName

object ClassicName:
  /** Alias for fromString. */
  def apply(input: String): ClassicName =
    fromString(input)

  /** Translate a string into a name by splitting it into words. The algorithm is designed
    * to work with most well-known naming conventions or mix of them. The general rule is that
    * consecutive letters and numbers are treated as words, upper-case letters and non-alphanumeric
    * characters start a new word.
    *
    * {{{
    * Name.fromString("fooBar_baz 123") // ClassicName("foo", "bar", "baz", "123")
    * Name.fromString("valueInUSD")     // ClassicName("value", "in", "u", "s", "d")
    * Name.fromString("ValueInUSD")     // ClassicName("value", "in", "u", "s", "d")
    * Name.fromString("value_in_USD")   // ClassicName("value", "in", "u", "s", "d")
    * Name.fromString("_-%")            // ClassicName()
    * }}}
    */

  def fromString(input: String): ClassicName =
    Name.classicName(input)

  def fromChunk(words: Chunk[String]): ClassicName = 
    ClassicName(Chunk(words.flatMap(s => Name.word(s.toLowerCase)).toList*))

  /** Convert a list of strings into a name.
   * This follows the pre-v4/morphir-elm rules; one Word per segment, and 
   * does no processing or validation of the words.
   * {{{
   * assert(fromList(List("foo", "bar", "baz", "123")) == ClassicName("foo-bar-baz-123"))
   * assert(fromList(List("value","in","u","s","d")) == ClassicName("value-in-u-s-d"))
   * }}}
  */
  def fromList(words: List[String]): ClassicName =
    Name.fromList(words).asInstanceOf[ClassicName]

  /** Turns a name into a camel-case string. 
   * {{{
   * ClassicName("fooBarBaz123").toCamelCase // "fooBarBaz123"
   * ClassicName("valueInUSD").toCamelCase // "valueInUSD"
   * }}}
  */
  def toCamelCase(name: ClassicName): String = name.toCamelCase
  def toSnakeCase(name: ClassicName): String = name.toSnakeCase
  def toHumanWords(name: ClassicName): List[String] = name.toHumanWords
  def toHumanWordsTitle(name: ClassicName): List[String] = name.toHumanWordsTitle

  /** Turns a name into a title-case string.
   * {{{
   * toTitleCase(fromList(List("foo", "bar", "baz", "123"))) // "FooBarBaz123"
   * toTitleCase(fromList(List("value","in","u","s","d"))) // "ValueInUSD"
   * }}}
  */
  def toTitleCase(name: ClassicName): String = name.toTitleCase

end ClassicName

final case class CanonicalName private[ir] (tokens: Chunk[Token]) extends Name:
  def toCanonicalString: String =
    tokens.toSeq.map(t => if t.isAcronym then s"(${Token.value(t).toLowerCase})" else Token.value(t)).mkString("-")

object CanonicalName:
  /** Build from list of words (each segment stored as Word token). */
  def fromList(words: List[String]): CanonicalName =
    Name.fromListAsCanonical(words)
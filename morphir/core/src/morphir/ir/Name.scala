package morphir.ir

import kyo.Chunk
import io.github.iltotore.iron.*
import io.github.iltotore.iron.constraint.string.*

import scala.util.matching.Regex
import Name.Token

/**
  * Name is a union of ClassicName (pre-v4 semantics) and CanonicalName (v4 semantics).
  * Use fold to handle the two variants.
  * API aligned with morphir-elm's Morphir.IR.Name: fromList, toList, fromString, toTitleCase, toCamelCase, toSnakeCase, toHumanWords, toHumanWordsTitle.
  */
sealed trait Name:
  def tokens: Chunk[Token]
  def toCanonicalString: String

  /** Convert name to list of segment strings (mirrors morphir-elm toList). */
  def toList: List[String] =
    tokens.toSeq.map(Token.value).toList

  /** Title-case string, e.g. "ValueInUSD" (morphir-elm toTitleCase). */
  def toTitleCase: String =
    toList.map(Name.capitalize).mkString

  /** Camel-case string, e.g. "valueInUSD" (morphir-elm toCamelCase). */
  def toCamelCase: String =
    toList match
      case Nil       => ""
      case h :: tail => (h :: tail.map(Name.capitalize)).mkString

  /** Snake-case string, e.g. "value_in_USD"; abbreviations as one word (morphir-elm toSnakeCase). */
  def toSnakeCase: String =
    toHumanWords.mkString("_")

  /** Human-readable words; single-letter runs coalesced to one upper-case word, e.g. ["value", "in", "USD"] (morphir-elm toHumanWords). */
  def toHumanWords: List[String] =
    Name.toHumanWordsFromList(toList)

  /** Like toHumanWords with first word capitalized, e.g. ["Value", "in", "USD"] (morphir-elm toHumanWordsTitle). */
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

  /** Build a name from a list of words (morphir-elm fromList); produces ClassicName. */
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
  private def word(s: String): Option[Name.Token] =
    s.refineOption[ValidWord].map(Token.Word.apply)

  private def acronym(s: String): Option[Name.Token] =
    s.refineOption[ValidAcronym].map(Token.Acronym.apply)

  // Classic parsing: morphir-elm behaviour — regex to only accept, one Word per segment
  private val classicWordPattern: Regex = """([a-zA-Z][a-z]*|[0-9]+)""".r
  private val canonicalPattern: Regex = """^([a-z0-9]+|\([a-z0-9]+\))(-([a-z0-9]+|\([a-z0-9]+\)))*$""".r

  /** Returns ClassicName directly for use by morphir-classic and tests. */
  def classicName(input: String): ClassicName =
    val segments = classicWordPattern.findAllIn(input).matchData.map(_.matched.toLowerCase).toList
    val toks = segments.flatMap(word).toList
    ClassicName(Chunk(toks*))

  def fromStringClassic(input: String): Name =
    classicName(input)

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

object ClassicName:
  /** Parse with pre-v4/morphir-elm rules; one Word per segment (morphir-elm fromString). */
  def apply(input: String): ClassicName =
    Name.classicName(input)
  /** Alias for apply; mirrors morphir-elm Name.fromString for classic parsing. */
  def fromString(input: String): ClassicName =
    apply(input)
  /** Build from list of words (morphir-elm fromList). */
  def fromList(words: List[String]): ClassicName =
    Name.fromList(words).asInstanceOf[ClassicName]
end ClassicName

final case class CanonicalName private[ir] (tokens: Chunk[Token]) extends Name:
  def toCanonicalString: String =
    tokens.toSeq.map(t => if t.isAcronym then s"(${Token.value(t).toLowerCase})" else Token.value(t)).mkString("-")

object CanonicalName:
  /** Build from list of words (each segment stored as Word token). */
  def fromList(words: List[String]): CanonicalName =
    Name.fromListAsCanonical(words)
package morphir.classic.ir

import morphir.ir.{ClassicName, Name as V4Name}
import neotype.*

/** Classic Morphir Name (v3/morphir-elm semantics): opaque type over `morphir.ir.ClassicName`.
  *
  * Represents human-readable identifiers made up of words, allowing the same identifiers
  * to work across various naming conventions (camelCase, TitleCase, snake_case, etc.).
  * Abbreviations are stored as individual single-letter words internally (e.g. "USD" becomes
  * `["u", "s", "d"]`) and coalesced back when formatting for human readability.
  *
  * {{{
  * val name = Name("valueInUSD")
  * name.toList           // List("value", "in", "u", "s", "d")
  * name.toTitleCase      // "ValueInUSD"
  * name.toCamelCase      // "valueInUSD"
  * name.toSnakeCase      // "value_in_USD"
  * }}}
  */
opaque type Name = Name.Type

object Name extends Subtype[ClassicName]:

  /** Parse a string into a Name using classic (morphir-elm) rules.
    *
    * The algorithm splits on upper-case letters and non-alphanumeric characters.
    * Each upper-case letter starts a new word; consecutive upper-case letters
    * become individual single-letter words.
    *
    * {{{
    * Name("fooBar_baz 123").toList // List("foo", "bar", "baz", "123")
    * Name("valueInUSD").toList     // List("value", "in", "u", "s", "d")
    * Name("_-%").toList            // List()
    * }}}
    */
  def apply(input:String):Name =
    Name(ClassicName.fromString(input))

  /** Alias for `apply`; mirrors morphir-elm `Name.fromString`.
    *
    * {{{
    * Name.fromString("valueInUSD").toList // List("value", "in", "u", "s", "d")
    * }}}
    */
  def fromString(input: String): Name =
    Name(ClassicName.fromString(input))

  /** Parse using classic (morphir-elm) rules explicitly.
    *
    * Equivalent to `fromString` for classic names.
    */
  def fromStringClassic(input: String): Name =
    Name(ClassicName(input))

  /** Build a Name from a list of words (morphir-elm `Name.fromList`).
    *
    * {{{
    * Name.fromList(List("value", "in", "u", "s", "d")).toTitleCase // "ValueInUSD"
    * }}}
    */
  def fromList(words: List[String]): Name =
    Name(ClassicName.fromList(words))

  extension (n: Name)

    /** Convert name to list of lowercase word strings (morphir-elm `Name.toList`).
      *
      * {{{
      * Name("fooBar_baz 123").toList // List("foo", "bar", "baz", "123")
      * Name("valueInUSD").toList     // List("value", "in", "u", "s", "d")
      * }}}
      */
    def toList: List[String] =
      n.toList

    /** Canonical string representation with words joined by hyphens.
      *
      * For classic names, all tokens are words (no acronym grouping):
      * {{{
      * Name("valueInUSD").toCanonicalString // "value-in-u-s-d"
      * }}}
      */
    def toCanonicalString: String =
      n.toCanonicalString

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
      n.toTitleCase

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
      n.toCamelCase

    /** Snake-case string (morphir-elm `Name.toSnakeCase`).
      *
      * Words are joined with underscores. Consecutive single-letter words
      * (abbreviations) are coalesced into one upper-case word.
      *
      * {{{
      * Name.fromList(List("foo", "bar", "baz", "123")).toSnakeCase   // "foo_bar_baz_123"
      * Name.fromList(List("value", "in", "u", "s", "d")).toSnakeCase // "value_in_USD"
      * }}}
      */
    def toSnakeCase: String =
      n.toSnakeCase

    /** Human-readable words (morphir-elm `Name.toHumanWords`).
      *
      * Like `toList` but consecutive single-letter words are coalesced
      * into one upper-case abbreviation.
      *
      * {{{
      * Name.fromList(List("value", "in", "u", "s", "d")).toHumanWords // List("value", "in", "USD")
      * Name.fromList(List("foo", "bar", "baz", "123")).toHumanWords   // List("foo", "bar", "baz", "123")
      * }}}
      */
    def toHumanWords: List[String] =
      n.toHumanWords

    /** Human-readable words with first word capitalized (morphir-elm `Name.toHumanWordsTitle`).
      *
      * {{{
      * Name.fromList(List("value", "in", "u", "s", "d")).toHumanWordsTitle // List("Value", "in", "USD")
      * }}}
      */
    def toHumanWordsTitle: List[String] =
      n.toHumanWordsTitle

package morphir.classic.ir

import morphir.ir.{ClassicName, Name as V4Name}

/**
  * Classic Morphir Name (v3 semantics): opaque type over morphir.ir.ClassicName.
  * Construction via V4Name.classicName; only classic behaviour is exposed.
  */
opaque type Name = ClassicName

object Name:
  def apply(input: String): Name =
    V4Name.classicName(input)

  def fromString(input: String): Name =
    V4Name.classicName(input)

  def fromStringClassic(input: String): Name =
    V4Name.classicName(input)

  def fromList(words: List[String]): Name =
    ClassicName.fromList(words)

  extension (n: Name)
    def toList: List[String] =
      n.toList

    def toCanonicalString: String =
      n.toCanonicalString

    def toTitleCase: String =
      n.toTitleCase

    def toCamelCase: String =
      n.toCamelCase

    def toSnakeCase: String =
      n.toSnakeCase

    def toHumanWords: List[String] =
      n.toHumanWords

    def toHumanWordsTitle: List[String] =
      n.toHumanWordsTitle

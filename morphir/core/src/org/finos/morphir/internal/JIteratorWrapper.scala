package org.finos.morphir.internal

import scala.collection.{ AbstractIterator, Iterator }

  /** Simple utility to avoid having either a dependency to scala-compat or a warning with 2.13.
   * Taken from the Laika codebase
    */
  case class JIteratorWrapper[A](underlying: java.util.Iterator[A]) extends AbstractIterator[A]
      with Iterator[A] {
    def hasNext: Boolean = underlying.hasNext
    def next(): A        = underlying.next
  }
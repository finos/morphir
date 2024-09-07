package org.finos.morphir.trees.ir

import scala.collection.BitSet

class Flags(bitset: BitSet):
  def isOpaqueType: Boolean = bitset.contains(Flags.OpaqueType)
object Flags:
  inline val OpaqueType = 1

package morphir.sdk

object Float {
  type Float = scala.Double
  object Float {
    def apply(value: java.lang.Number): Float = value.doubleValue()
    def apply(value: scala.Double): Float     = value
    def apply(value: scala.Float): Float      = value.doubleValue()
  }
}

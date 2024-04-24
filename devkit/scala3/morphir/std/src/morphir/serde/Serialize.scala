package morphir.serde
import morphir.std.result.Result

trait Serialize[-Self] {
  def serialize[S <: Serializer](
      self: Self,
      serializer: S
  ): Result[serializer.Error, serializer.Ok]
}

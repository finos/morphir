package morphir.runtime.internal
import morphir.cdk.*
import morphir.cdk.IntoName.given
import izumi.reflect.*

enum Symbol[A]:
  case Variable(name: Name, tag: Tag[A])
  case Function(fqName: FQName, tag: Tag[A])

object Symbol:
  def named[Input](input: Input): FromOps[Input] = FromOps[Input](input)
  final class FromOps[Input](input: Input) extends AnyVal:
    def asVariableOf[A](using tag: Tag[A])(using IntoName[Input]): Symbol[A] =
      Symbol.Variable(input.intoName, tag)

    def asFunctionOf[A](using tag: Tag[A])(using IntoFQName[Input]): Symbol[A] =
      Symbol.Function(input.intoFQName, tag)

enum VariableValue[+A]:
  case ExternalConst(value: A)

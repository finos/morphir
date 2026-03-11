package morphir.ir
import AccessControlled.Access

final case class AccessControlled[+A](access: Access, value: A) extends Product with Serializable
object AccessControlled:

    enum Access:
        case Public
        case Private
package morphir.ir

/** Generated based on IR.AccessControlled
*/
object AccessControlled{

  sealed trait Access {
  
    
  
  }
  
  object Access{
  
    case object Private extends morphir.ir.AccessControlled.Access{}
    
    case object Public extends morphir.ir.AccessControlled.Access{}
  
  }
  
  val Private: morphir.ir.AccessControlled.Access.Private.type  = morphir.ir.AccessControlled.Access.Private
  
  val Public: morphir.ir.AccessControlled.Access.Public.type  = morphir.ir.AccessControlled.Access.Public
  
  final case class AccessControlled[A](
    access: morphir.ir.AccessControlled.Access,
    value: A
  ){}
  
  def map[A, B](
    f: A => B
  )(
    ac: morphir.ir.AccessControlled.AccessControlled[A]
  ): morphir.ir.AccessControlled.AccessControlled[B] =
    (morphir.ir.AccessControlled.AccessControlled(
      ac.access,
      f(ac.value)
    ) : morphir.ir.AccessControlled.AccessControlled[B])
  
  def _private[A](
    value: A
  ): morphir.ir.AccessControlled.AccessControlled[A] =
    (morphir.ir.AccessControlled.AccessControlled(
      (morphir.ir.AccessControlled.Private : morphir.ir.AccessControlled.Access),
      value
    ) : morphir.ir.AccessControlled.AccessControlled[A])
  
  def public[A](
    value: A
  ): morphir.ir.AccessControlled.AccessControlled[A] =
    (morphir.ir.AccessControlled.AccessControlled(
      (morphir.ir.AccessControlled.Public : morphir.ir.AccessControlled.Access),
      value
    ) : morphir.ir.AccessControlled.AccessControlled[A])
  
  def withAccess[A](
    access: morphir.ir.AccessControlled.Access
  )(
    ac: morphir.ir.AccessControlled.AccessControlled[A]
  ): morphir.sdk.Maybe.Maybe[A] =
    access match {
      case morphir.ir.AccessControlled.Public => 
        morphir.ir.AccessControlled.withPublicAccess(ac)
      case morphir.ir.AccessControlled.Private => 
        (morphir.sdk.Maybe.Just(morphir.ir.AccessControlled.withPrivateAccess(ac)) : morphir.sdk.Maybe.Maybe[A])
    }
  
  def withPrivateAccess[A](
    ac: morphir.ir.AccessControlled.AccessControlled[A]
  ): A =
    ac.access match {
      case morphir.ir.AccessControlled.Public => 
        ac.value
      case morphir.ir.AccessControlled.Private => 
        ac.value
    }
  
  def withPublicAccess[A](
    ac: morphir.ir.AccessControlled.AccessControlled[A]
  ): morphir.sdk.Maybe.Maybe[A] =
    ac.access match {
      case morphir.ir.AccessControlled.Public => 
        (morphir.sdk.Maybe.Just(ac.value) : morphir.sdk.Maybe.Maybe[A])
      case morphir.ir.AccessControlled.Private => 
        (morphir.sdk.Maybe.Nothing : morphir.sdk.Maybe.Maybe[A])
    }

}
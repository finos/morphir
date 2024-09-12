package org.finos.morphir.config
import kyo.* 
import metaconfig.*


trait ToConfigured[E,A, R[+_,+_]]:
    extension (result:R[E,A])
        def toConfigured(stackSize:Int = 10): Configured[A]    

object ToConfigured:
    given [A]:ToConfigured[Throwable,A,Result] with
        extension (result:Result[Throwable,A])
            def toConfigured(stackSize:Int = 10): Configured[A] = result match
                case Result.Success(value) => Configured.Ok(value)
                case Result.Panic(exception) => Configured.exception(exception, stackSize = stackSize)
                case Result.Fail(error) => Configured.exception(error, stackSize = stackSize)            
    
    given [A]:ToConfigured[String,A,Result] with
        extension (result:Result[String,A])
            def toConfigured(stackSize:Int = 10): Configured[A] = result match
                case Result.Success(value) => Configured.Ok(value)
                case Result.Panic(exception) => Configured.exception(exception, stackSize = stackSize)
                case Result.Fail(error) => Configured.error(error)
    
    given [A]:ToConfigured[Throwable,A,Either] with
        extension (result:Either[Throwable,A])
            def toConfigured(stackSize:Int = 10): Configured[A] = result match
                case Right(value) => Configured.Ok(value)
                case Left(error) => Configured.exception(error, stackSize = stackSize)        
    
    given [A]:ToConfigured[String,A,Either] with
        extension (result:Either[String,A])
            def toConfigured(stackSize:Int = 10): Configured[A] = result match
            case Right(value) => Configured.Ok(value)
            case Left(error) => Configured.error(error)                  

extension [E,A,R[+_,+_]] (result:R[E,A])(using instance:ToConfigured[E,A,R])
    def toConfigured(stackSize:Int = 10): Configured[A] = instance.toConfigured(result)(stackSize = stackSize)
    
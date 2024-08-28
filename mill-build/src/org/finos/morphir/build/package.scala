package org.finos.morphir
import upickle.default.{ReadWriter => RW, macroRW}
package object build {
    case class BeforeArgs(toSeq:Seq[String]) extends AnyVal {
        def ++(args:Seq[String]) = BeforeArgs(toSeq ++ args)
        def ++:(args:Seq[String]) = BeforeArgs(args ++ toSeq)
    }

    object BeforeArgs {
        val empty = BeforeArgs(Seq.empty)
        implicit val rw:RW[BeforeArgs] = macroRW
    }

    case class AfterArgs(toSeq:Seq[String]) extends AnyVal{
        def ++(args:Seq[String]) = AfterArgs(toSeq ++ args)
        def ++:(args:Seq[String]) = AfterArgs(args ++ toSeq)
    }

    object AfterArgs {
        val empty = AfterArgs(Seq.empty)
        implicit val rw:RW[AfterArgs] = macroRW
    }    

    case class Args(toSeq:Seq[String]) extends AnyVal {
        def ++(args:Seq[String]) = Args(toSeq ++ args)
        def ++:(args:Seq[String]) = Args(args ++ toSeq)
    }

    object Args {
        val empty = Args(Seq.empty)
        implicit val rw:RW[Args] = macroRW
    }

    case class SubcommandArgs(toSeq:Seq[String]) extends AnyVal {
        def ++(args:Seq[String]) = SubcommandArgs(toSeq ++ args)
        def ++:(args:Seq[String]) = SubcommandArgs(args ++ toSeq)
    }

    object SubcommandArgs {
        val empty = SubcommandArgs(Seq.empty)
        implicit val rw:RW[SubcommandArgs] = macroRW
        def apply(first:String, args:String*):SubcommandArgs = SubcommandArgs(first +: args)

        
    }

    implicit object PathRead extends mainargs.TokensReader.Simple[os.Path]{
        def shortName = "path"
        def read(strs: Seq[String]) = Right(os.Path(strs.head, os.pwd))
    }
}


package org.finos.morphir.build

import org.finos.morphir.build.{Args, BeforeArgs, AfterArgs}
import upickle.default.{ReadWriter => RW, macroRW}

final case class CommandLine(
    command:String, 
    subcommandArgs:SubcommandArgs = SubcommandArgs.empty,
    args:Args = Args.empty, 
    beforeArgs:BeforeArgs = BeforeArgs.empty, 
    afterArgs:AfterArgs = AfterArgs.empty) { self =>        

    def ++(subcommandArgs:SubcommandArgs) = appendSubcommandArgs(subcommandArgs.toSeq)

    def toSeq:Seq[String] = Seq(command) ++ subcommandArgs.toSeq ++ beforeArgs.toSeq ++ args.toSeq ++ afterArgs.toSeq

    def appendArgs(newArgs:Seq[String]) = copy(args = args ++ newArgs)
    def appendBeforeArgs(newArgs:Seq[String]) = copy(beforeArgs = beforeArgs ++ newArgs)
    def prependArgs(newArgs:Seq[String]) = copy(args = newArgs ++: args)    
    def prependBeforeArgs(newArgs:Seq[String]) = copy(beforeArgs = newArgs ++: beforeArgs)
    def appendAfterArgs(newArgs:Seq[String]) = copy(afterArgs = afterArgs ++ newArgs)
    def prependAfterArgs(newArgs:Seq[String]) = copy(afterArgs = newArgs ++: afterArgs)    
    def appendSubcommandArgs(newArgs:Seq[String]) = copy(subcommandArgs = subcommandArgs ++ newArgs)
    def prependSubcommandArgs(newArgs:Seq[String]) = copy(subcommandArgs = newArgs ++: subcommandArgs)
    def withArgs(args:String*) = copy(args = Args(args))    
    def withBeforeArgs(args:String*) = copy(beforeArgs = BeforeArgs(args))
    def withAfterArgs(args:String*) = copy(afterArgs = AfterArgs(args))
    def withCommand(newCommand:String) = copy(command = newCommand)
    def withSubcommandArgs(args:String*) = copy(subcommandArgs = SubcommandArgs(args))

    override def toString():String = toSeq.mkString(" ")
}

object CommandLine {
    implicit val rw:RW[CommandLine] = macroRW
    val Elm = CommandLine("elm")
    val Shelm = Elm.withCommand("shelm")
}
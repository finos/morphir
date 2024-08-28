package org.finos.morphir.build

trait ToCommandLine[Self] {
  def toCommandLine(self: Self): CommandLine
}

object ToCommandLine {
    def apply[A](implicit tc: ToCommandLine[A]): ToCommandLine[A] = tc
    def instance[A](f: A => CommandLine): ToCommandLine[A] = new ToCommandLine[A] {
        def toCommandLine(self: A): CommandLine = f(self)
    }

    implicit class Ops[A](val self: A) extends AnyVal {
        def toCommandLine(implicit instance:ToCommandLine[A]): CommandLine = 
            instance.toCommandLine(self)
    }
}

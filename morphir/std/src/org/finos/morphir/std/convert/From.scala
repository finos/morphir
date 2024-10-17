package org.finos.morphir.std.convert

trait From[-T, +U] extends Function[T,U]:
    /// Convert a value of type `T` to `Self`
    def from(value:T):U 
    def apply(value:T):U = from(value)


object From:
    given [T, Self](using Conversion[T,Self]):From[T,Self] with
        def from(value:T):Self = value

    def from[T, Self](value:T)(using From[T,Self]):Self = summon[From[T,Self]](value)

    extension [Input](input:Input) 
        def convertTo[Output](using instance:From[Input,Output]):Output = instance.from(input)

trait Into[-Self, +T]:
    /// Convert a value of type `Self` to `T`
    extension (value:Self) def into:T

object Into:
    given [Self,T](using Conversion[Self,T]):Into[Self,T] with
        extension (value:Self) def into:T = value
namespace Morphir.IR

open Morphir.IR.Name

type IRNode<'T> =
    abstract member Attributes: 'T

module IRNode =
    let inline attributes<'T, 'A when 'T: (member Attributes: 'A)> (node: 'T) = node.Attributes

type Type<'A> =
    | Unit of Attributes: 'A
    | Variable of Attributes: 'A * Name: Name

    interface IRNode<'A> with
        member this.Attributes =
            match this with
            | Unit a -> a
            | Variable(a, _) -> a

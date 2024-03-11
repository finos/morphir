namespace Morphir.IR

type IHaveAttribution<'A> =
    abstract member Attributes: 'A

type Expression<'A> =
    inherit IHaveAttribution<'A>

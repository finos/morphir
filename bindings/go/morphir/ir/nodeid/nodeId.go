package nodeid

import "github.com/finos/morphir/bindings/go/morphir/ir/name"

type Tag int8
type NodePathStepTag int8

const (
	TypeIdTag Tag = iota
	ValueIdTag
	ModuleIdTag
)

const (
	ChildByNameTag NodePathStepTag = iota
	ChildByIndexTag
)

type NodeID struct {
	Tag Tag
}

type NodePathStep struct {
	Tag          NodePathStepTag
	childByName  *name.Name
	childByIndex int
}

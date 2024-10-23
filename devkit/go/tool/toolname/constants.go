package toolname

type ToolName string

const (
	Morphir ToolName = "morphir"
	Emerald ToolName = "emerald"
	Empty   ToolName = ""
)

func (t *ToolName) IsEmpty() bool {
	return t == nil || *t == Empty
}

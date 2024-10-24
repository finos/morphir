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

func (t *ToolName) IsUnknown() bool {
	return t.IsEmpty() || (*t != Morphir && *t != Emerald)
}

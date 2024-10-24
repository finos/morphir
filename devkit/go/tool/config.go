package tool

import (
	"fmt"
	"github.com/finos/morphir/devkit/go/tool/toolname"
)

func ConfigFileBaseName(toolName toolname.ToolName) string {
	switch toolName {
	case toolname.Morphir:
		return ".morphir"
	case toolname.Emerald:
		return ".emerald"
	default:
		return fmt.Sprintf(".%s", toolName)
	}
}

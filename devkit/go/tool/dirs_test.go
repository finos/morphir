package tool

import (
	"strings"
	"testing"

	"github.com/finos/morphir/devkit/go/tool/toolname"
	"github.com/life4/genesis/slices"
)

type Assertion[T any] func(actual T, err error)

func TestTool_GetUserConfigDirs(t *testing.T) {
	testCases := []struct {
		name      string
		toolName  toolname.ToolName
		assertion Assertion[[]UserConfigDir]
	}{
		{"morphir", toolname.Morphir, func(dirs []UserConfigDir, err error) {
			if err != nil {
				t.Errorf("unexpected error: %v", err)
			}

			if !slices.All(dirs, func(dir UserConfigDir) bool {
				return strings.Contains(string(dir), "finos/morphir")

			}) {
				t.Errorf("expected all dirs to contain 'finos/morphir', but got: %+q", dirs)
			}
		}},
		{"emerald", toolname.Emerald, func(dirs []UserConfigDir, err error) {
			if err != nil {
				t.Errorf("unexpected error: %+q", err)
			}

			if !slices.All(dirs, func(dir UserConfigDir) bool {
				return strings.Contains(string(dir), "finos/emerald")

			}) {
				t.Errorf("expected all dirs to contain 'finos/emerald'")
			}
		}},
		{"unknown", toolname.ToolName("unknown"), func(dirs []UserConfigDir, err error) {
			if err != nil {
				t.Errorf("unexpected error: %+q", err)
			}

			if !slices.All(dirs, func(dir UserConfigDir) bool {
				dirStr := string(dir)
				// Only morphir and emerald tools should default to finos vendor
				return strings.Contains(dirStr, "unknown") && !strings.Contains(dirStr, "finos")

			}) {
				t.Errorf("expected all dirs to contain 'unknown' and not 'finos', but got: %+q", dirs)
			}
		}},
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			actual, err := GetUserConfigDirs(tc.toolName)
			tc.assertion(actual, err)

		})
	}

}

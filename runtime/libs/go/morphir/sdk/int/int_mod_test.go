package int

import (
	"fmt"
	"github.com/finos/morphir/runtime/libs/go/morphir/sdk/basics"
	"testing"
)

func TestInt_FromInt8(t *testing.T) {
	testCases := []struct {
		input Int8
		want  basics.Int
	}{
		{0, 0},
	}

	for _, tc := range testCases {
		name := fmt.Sprintf(`Given an Int8(%v)`, tc.input)
		t.Run(name, func(t *testing.T) {
			got := FromInt8(tc.input)
			if got != tc.want {
				t.Errorf("got %v; want %v", got, tc.want)
			}
		})
	}
}

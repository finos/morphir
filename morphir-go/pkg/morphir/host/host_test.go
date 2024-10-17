package host

import (
	"github.com/finos/morphir/morphir-go/pkg/morphir/paths"
	"testing"

	"github.com/sanity-io/litter"
)

func TestNewHost(t *testing.T) {
	t.Run("A New Host should be of Kind Morphir", func(t *testing.T) {
		sut := New()
		actual := sut.Kind()
		if actual != Morphir {
			t.Errorf("New Host should be of Kind Morphir, but was %v", actual)
		}
	})
}

func TestNewHost_Having_Morphir_Kind(t *testing.T) {
	litter.Config.HidePrivateFields = false
	sut := New(
		WithKind(Morphir),
	)
	t.Run("should have a Default configMode", func(t *testing.T) {
		if !sut.configMode.IsDefault() {
			t.Errorf("Config mode should be Default, but was %v", sut.configMode)
		}
	})
	t.Run("should have an os.FS and a set workingDir", func(t *testing.T) {
		sut = New(WithKind(Morphir), WithOsFS())
		litter.Dump(sut)
		if sut.fs == nil {
			t.Errorf("New Host should have a non-nil FS")
		}
		workingDir, ok := sut.paths.WorkingDir()
		if !ok {
			t.Errorf("New Host should have a WorkingDir")
		}
		wd := string(workingDir)
		const pattern = "**/pkg/morphir/host"
		matched, _ := paths.Match(pattern, wd)
		if !matched {
			t.Errorf("New Host should have a workingDir matching the glob %v, but %v did not match", pattern, wd)
		}
	})
}

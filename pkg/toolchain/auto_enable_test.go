package toolchain

import (
	"testing"

	"github.com/finos/morphir/pkg/vfs"
	"github.com/stretchr/testify/assert"
)

func TestAutoEnableContext_FileExists(t *testing.T) {
	// Create a memory VFS with some files
	root := vfs.NewMemFolder(vfs.MustVPath("/"), vfs.Meta{}, vfs.Origin{MountName: "mem"}, []vfs.Entry{
		vfs.NewMemFile(vfs.MustVPath("/elm.json"), vfs.Meta{}, vfs.Origin{MountName: "mem"}, []byte("{}")),
		vfs.NewMemFile(vfs.MustVPath("/morphir.json"), vfs.Meta{}, vfs.Origin{MountName: "mem"}, []byte("{}")),
		vfs.NewMemFolder(vfs.MustVPath("/src"), vfs.Meta{}, vfs.Origin{MountName: "mem"}, []vfs.Entry{
			vfs.NewMemFile(vfs.MustVPath("/src/Main.elm"), vfs.Meta{}, vfs.Origin{MountName: "mem"}, []byte("")),
		}),
	})
	overlay := vfs.NewOverlayVFS([]vfs.Mount{{Name: "mem", Mode: vfs.MountRW, Root: root}})

	ctx := AutoEnableContext{
		VFS:         overlay,
		ProjectRoot: vfs.MustVPath("/"),
	}

	t.Run("existing file returns true", func(t *testing.T) {
		assert.True(t, ctx.FileExists("elm.json"))
		assert.True(t, ctx.FileExists("morphir.json"))
	})

	t.Run("non-existing file returns false", func(t *testing.T) {
		assert.False(t, ctx.FileExists("go.mod"))
		assert.False(t, ctx.FileExists("nonexistent.txt"))
	})

	t.Run("nested file exists", func(t *testing.T) {
		assert.True(t, ctx.FileExists("src/Main.elm"))
	})
}

func TestAutoEnableContext_HasAllFiles(t *testing.T) {
	root := vfs.NewMemFolder(vfs.MustVPath("/"), vfs.Meta{}, vfs.Origin{MountName: "mem"}, []vfs.Entry{
		vfs.NewMemFile(vfs.MustVPath("/elm.json"), vfs.Meta{}, vfs.Origin{MountName: "mem"}, []byte("{}")),
		vfs.NewMemFile(vfs.MustVPath("/morphir.json"), vfs.Meta{}, vfs.Origin{MountName: "mem"}, []byte("{}")),
	})
	overlay := vfs.NewOverlayVFS([]vfs.Mount{{Name: "mem", Mode: vfs.MountRW, Root: root}})

	ctx := AutoEnableContext{
		VFS:         overlay,
		ProjectRoot: vfs.MustVPath("/"),
	}

	t.Run("all files exist returns true", func(t *testing.T) {
		assert.True(t, ctx.HasAllFiles("elm.json", "morphir.json"))
	})

	t.Run("missing one file returns false", func(t *testing.T) {
		assert.False(t, ctx.HasAllFiles("elm.json", "go.mod"))
	})

	t.Run("all files missing returns false", func(t *testing.T) {
		assert.False(t, ctx.HasAllFiles("go.mod", "go.work"))
	})
}

func TestAutoEnableContext_HasAnyFile(t *testing.T) {
	root := vfs.NewMemFolder(vfs.MustVPath("/"), vfs.Meta{}, vfs.Origin{MountName: "mem"}, []vfs.Entry{
		vfs.NewMemFile(vfs.MustVPath("/elm.json"), vfs.Meta{}, vfs.Origin{MountName: "mem"}, []byte("{}")),
	})
	overlay := vfs.NewOverlayVFS([]vfs.Mount{{Name: "mem", Mode: vfs.MountRW, Root: root}})

	ctx := AutoEnableContext{
		VFS:         overlay,
		ProjectRoot: vfs.MustVPath("/"),
	}

	t.Run("one file exists returns true", func(t *testing.T) {
		assert.True(t, ctx.HasAnyFile("elm.json", "morphir.json"))
	})

	t.Run("first file exists returns true", func(t *testing.T) {
		assert.True(t, ctx.HasAnyFile("elm.json", "go.mod"))
	})

	t.Run("no files exist returns false", func(t *testing.T) {
		assert.False(t, ctx.HasAnyFile("go.mod", "go.work"))
	})
}

func TestAutoEnableContext_HasMatchingFiles(t *testing.T) {
	root := vfs.NewMemFolder(vfs.MustVPath("/"), vfs.Meta{}, vfs.Origin{MountName: "mem"}, []vfs.Entry{
		vfs.NewMemFile(vfs.MustVPath("/example.wit"), vfs.Meta{}, vfs.Origin{MountName: "mem"}, []byte("")),
		vfs.NewMemFolder(vfs.MustVPath("/wit"), vfs.Meta{}, vfs.Origin{MountName: "mem"}, []vfs.Entry{
			vfs.NewMemFile(vfs.MustVPath("/wit/types.wit"), vfs.Meta{}, vfs.Origin{MountName: "mem"}, []byte("")),
		}),
	})
	overlay := vfs.NewOverlayVFS([]vfs.Mount{{Name: "mem", Mode: vfs.MountRW, Root: root}})

	ctx := AutoEnableContext{
		VFS:         overlay,
		ProjectRoot: vfs.MustVPath("/"),
	}

	t.Run("glob matches root files", func(t *testing.T) {
		assert.True(t, ctx.HasMatchingFiles("*.wit"))
	})

	t.Run("glob matches nested files", func(t *testing.T) {
		assert.True(t, ctx.HasMatchingFiles("**/*.wit"))
	})

	t.Run("glob no matches", func(t *testing.T) {
		assert.False(t, ctx.HasMatchingFiles("*.go"))
	})
}

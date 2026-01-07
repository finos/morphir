package docling

import (
	"testing"

	"github.com/stretchr/testify/require"
)

func TestItemLabelIsValid(t *testing.T) {
	tests := []struct {
		name  string
		label ItemLabel
		valid bool
	}{
		{"Valid text", LabelText, true},
		{"Valid table", LabelTable, true},
		{"Valid picture", LabelPicture, true},
		{"Invalid empty", ItemLabel(""), false},
		{"Invalid custom", ItemLabel("custom"), false},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			require.Equal(t, tt.valid, tt.label.IsValid())
		})
	}
}

func TestRefIsEmpty(t *testing.T) {
	require.True(t, Ref("").IsEmpty())
	require.False(t, Ref("ref1").IsEmpty())
}

func TestRefEqual(t *testing.T) {
	ref1 := Ref("ref1")
	ref2 := Ref("ref1")
	ref3 := Ref("ref2")

	require.True(t, ref1.Equal(ref2))
	require.False(t, ref1.Equal(ref3))
}

func TestBoundingBoxGeometry(t *testing.T) {
	bbox := NewBoundingBox(10, 20, 100, 50, 1)

	require.Equal(t, 10.0, bbox.Left)
	require.Equal(t, 20.0, bbox.Top)
	require.Equal(t, 100.0, bbox.Width)
	require.Equal(t, 50.0, bbox.Height)
	require.Equal(t, 1, bbox.Page)
	require.Equal(t, 110.0, bbox.Right())
	require.Equal(t, 70.0, bbox.Bottom())
}

func TestBoundingBoxContains(t *testing.T) {
	bbox := NewBoundingBox(10, 20, 100, 50, 1)

	require.True(t, bbox.Contains(15, 25))
	require.True(t, bbox.Contains(10, 20))
	require.True(t, bbox.Contains(110, 70))
	require.False(t, bbox.Contains(5, 25))
	require.False(t, bbox.Contains(15, 15))
}

func TestBoundingBoxIntersects(t *testing.T) {
	bbox1 := NewBoundingBox(10, 20, 100, 50, 1)
	bbox2 := NewBoundingBox(50, 40, 100, 50, 1)
	bbox3 := NewBoundingBox(200, 200, 50, 50, 1)
	bbox4 := NewBoundingBox(50, 40, 100, 50, 2) // Different page

	require.True(t, bbox1.Intersects(bbox2))
	require.True(t, bbox2.Intersects(bbox1))
	require.False(t, bbox1.Intersects(bbox3))
	require.False(t, bbox1.Intersects(bbox4))
}

func TestProvenanceImmutability(t *testing.T) {
	prov := NewProvenanceItem(1)
	bbox := NewBoundingBox(10, 20, 100, 50, 1)

	// WithBoundingBox should return a new instance
	provWithBBox := prov.WithBoundingBox(bbox)
	require.Nil(t, prov.BBox)
	require.NotNil(t, provWithBBox.BBox)

	// WithCharRange should return a new instance
	provWithRange := prov.WithCharRange(0, 10)
	require.Equal(t, 0, prov.CharStart)
	require.Equal(t, 0, prov.CharEnd)
	require.Equal(t, 0, provWithRange.CharStart)
	require.Equal(t, 10, provWithRange.CharEnd)

	// WithMetadata should return a new instance
	provWithMeta := prov.WithMetadata("key", "value")
	require.Empty(t, prov.Metadata)
	require.Equal(t, "value", provWithMeta.Metadata["key"])
}

func TestMetadataImmutability(t *testing.T) {
	meta := NewMetadata()
	meta2 := meta.With("key1", "value1")
	meta3 := meta2.With("key2", "value2")

	// Original should be unchanged
	require.Empty(t, meta)
	require.Len(t, meta2, 1)
	require.Len(t, meta3, 2)

	val, ok := meta3.GetString("key1")
	require.True(t, ok)
	require.Equal(t, "value1", val)

	val2, ok := meta3.GetString("key2")
	require.True(t, ok)
	require.Equal(t, "value2", val2)
}

func TestMetadataGetInt(t *testing.T) {
	meta := NewMetadata().With("int", 42).With("float", 3.14)

	intVal, ok := meta.GetInt("int")
	require.True(t, ok)
	require.Equal(t, 42, intVal)

	// Should handle float64 from JSON
	floatVal, ok := meta.GetInt("float")
	require.True(t, ok)
	require.Equal(t, 3, floatVal)

	_, ok = meta.GetInt("missing")
	require.False(t, ok)
}

func TestMetadataJSON(t *testing.T) {
	meta := NewMetadata().With("key1", "value1").With("key2", 42)

	data, err := meta.MarshalJSON()
	require.NoError(t, err)
	require.NotEmpty(t, data)

	var meta2 Metadata
	err = meta2.UnmarshalJSON(data)
	require.NoError(t, err)

	val, ok := meta2.GetString("key1")
	require.True(t, ok)
	require.Equal(t, "value1", val)

	// JSON numbers are float64
	intVal, ok := meta2.GetInt("key2")
	require.True(t, ok)
	require.Equal(t, 42, intVal)
}

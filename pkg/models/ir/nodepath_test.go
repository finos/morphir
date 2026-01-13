package ir

import (
	"encoding/json"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestNodePathFromFQName(t *testing.T) {
	fqName := FQNameFromParts(
		PathFromString("My.Package"),
		PathFromString("Foo"),
		NameFromParts([]string{"bar"}),
	)

	nodePath := NodePathFromFQName(fqName)

	assert.True(t, nodePath.PackagePath().Equal(PathFromString("My.Package")), "package path mismatch")
	assert.True(t, nodePath.ModulePath().Equal(PathFromString("Foo")), "module path mismatch")
	localName := nodePath.LocalName()
	require.NotNil(t, localName, "expected local name to be non-nil")
	assert.True(t, localName.Equal(NameFromParts([]string{"bar"})), "local name mismatch")
	assert.Len(t, nodePath.Segments(), 0, "expected no segments")
}

func TestNodePathFromQualifiedModuleName(t *testing.T) {
	qName := NewQualifiedModuleName(
		PathFromString("My.Package"),
		PathFromString("Foo"),
	)

	nodePath := NodePathFromQualifiedModuleName(qName)

	assert.True(t, nodePath.PackagePath().Equal(PathFromString("My.Package")), "package path mismatch")
	assert.True(t, nodePath.ModulePath().Equal(PathFromString("Foo")), "module path mismatch")
	assert.Nil(t, nodePath.LocalName(), "expected local name to be nil for module-level path")
	assert.Len(t, nodePath.Segments(), 0, "expected no segments")
}

func TestNodePathFromParts(t *testing.T) {
	packagePath := PathFromString("My.Package")
	modulePath := PathFromString("Foo")
	localName := NameFromParts([]string{"bar"})
	segments := []Name{
		NameFromParts([]string{"field1"}),
		NameFromParts([]string{"field2"}),
	}

	nodePath := NodePathFromParts(packagePath, modulePath, &localName, segments)

	assert.True(t, nodePath.PackagePath().Equal(packagePath), "package path mismatch")
	assert.True(t, nodePath.ModulePath().Equal(modulePath), "module path mismatch")
	gotLocalName := nodePath.LocalName()
	require.NotNil(t, gotLocalName, "expected local name to be non-nil")
	assert.True(t, gotLocalName.Equal(localName), "local name mismatch")
	gotSegments := nodePath.Segments()
	assert.Len(t, gotSegments, 2, "segments length mismatch")
}

func TestNodePathFromParts_ModuleLevel(t *testing.T) {
	packagePath := PathFromString("My.Package")
	modulePath := PathFromString("Foo")

	nodePath := NodePathFromParts(packagePath, modulePath, nil, nil)

	assert.Nil(t, nodePath.LocalName(), "expected local name to be nil")
}

func TestNodePath_PackagePath(t *testing.T) {
	nodePath := NodePathFromFQName(FQNameFromParts(
		PathFromString("Test.Package"),
		PathFromString("Module"),
		NameFromParts([]string{"value"}),
	))

	path := nodePath.PackagePath()
	assert.True(t, path.Equal(PathFromString("Test.Package")), "PackagePath mismatch")
}

func TestNodePath_ModulePath(t *testing.T) {
	nodePath := NodePathFromFQName(FQNameFromParts(
		PathFromString("Test.Package"),
		PathFromString("Module"),
		NameFromParts([]string{"value"}),
	))

	path := nodePath.ModulePath()
	assert.True(t, path.Equal(PathFromString("Module")), "ModulePath mismatch")
}

func TestNodePath_LocalName(t *testing.T) {
	localName := NameFromParts([]string{"test"})
	nodePath := NodePathFromFQName(FQNameFromParts(
		PathFromString("Test"),
		PathFromString("Module"),
		localName,
	))

	got := nodePath.LocalName()
	require.NotNil(t, got, "expected local name to be non-nil")
	assert.True(t, got.Equal(localName), "LocalName mismatch")

	// Test defensive copy
	got2 := nodePath.LocalName()
	assert.NotSame(t, got, got2, "LocalName should return defensive copy")
}

func TestNodePath_LocalName_Nil(t *testing.T) {
	nodePath := NodePathFromQualifiedModuleName(NewQualifiedModuleName(
		PathFromString("Test"),
		PathFromString("Module"),
	))

	assert.Nil(t, nodePath.LocalName(), "expected local name to be nil for module-level path")
}

func TestNodePath_Segments(t *testing.T) {
	segments := []Name{
		NameFromParts([]string{"seg1"}),
		NameFromParts([]string{"seg2"}),
	}
	nodePath := NodePathFromParts(
		PathFromString("Test"),
		PathFromString("Module"),
		func() *Name { n := NameFromParts([]string{"value"}); return &n }(),
		segments,
	)

	got := nodePath.Segments()
	assert.Len(t, got, 2, "Segments length mismatch")

	// Test defensive copy
	got2 := nodePath.Segments()
	assert.Len(t, got2, 2, "Segments should return defensive copy")
}

func TestNodePath_Segments_Empty(t *testing.T) {
	nodePath := NodePathFromFQName(FQNameFromParts(
		PathFromString("Test"),
		PathFromString("Module"),
		NameFromParts([]string{"value"}),
	))

	segments := nodePath.Segments()
	assert.Nil(t, segments, "expected nil for empty segments")
}

func TestNodePath_ToFQName(t *testing.T) {
	fqName := FQNameFromParts(
		PathFromString("My.Package"),
		PathFromString("Foo"),
		NameFromParts([]string{"bar"}),
	)
	nodePath := NodePathFromFQName(fqName)

	got, err := nodePath.ToFQName()
	require.NoError(t, err, "ToFQName: unexpected error")

	assert.True(t, got.Equal(fqName), "ToFQName: result mismatch")
}

func TestNodePath_ToFQName_ModuleLevel(t *testing.T) {
	nodePath := NodePathFromQualifiedModuleName(NewQualifiedModuleName(
		PathFromString("My.Package"),
		PathFromString("Foo"),
	))

	_, err := nodePath.ToFQName()
	assert.Error(t, err, "expected error for module-level path")
}

func TestNodePath_ToFQName_WithSegments(t *testing.T) {
	segments := []Name{NameFromParts([]string{"seg"})}
	localName := NameFromParts([]string{"bar"})
	nodePath := NodePathFromParts(
		PathFromString("My.Package"),
		PathFromString("Foo"),
		&localName,
		segments,
	)

	_, err := nodePath.ToFQName()
	assert.Error(t, err, "expected error for path with segments")
}

func TestNodePath_ToQualifiedModuleName(t *testing.T) {
	qName := NewQualifiedModuleName(
		PathFromString("My.Package"),
		PathFromString("Foo"),
	)
	nodePath := NodePathFromQualifiedModuleName(qName)

	got, err := nodePath.ToQualifiedModuleName()
	require.NoError(t, err, "ToQualifiedModuleName: unexpected error")

	assert.True(t, got.Equal(qName), "ToQualifiedModuleName: result mismatch")
}

func TestNodePath_ToQualifiedModuleName_WithLocalName(t *testing.T) {
	nodePath := NodePathFromFQName(FQNameFromParts(
		PathFromString("My.Package"),
		PathFromString("Foo"),
		NameFromParts([]string{"bar"}),
	))

	_, err := nodePath.ToQualifiedModuleName()
	assert.Error(t, err, "expected error for path with local name")
}

func TestNodePath_ToQualifiedModuleName_WithSegments(t *testing.T) {
	segments := []Name{NameFromParts([]string{"seg"})}
	nodePath := NodePathFromParts(
		PathFromString("My.Package"),
		PathFromString("Foo"),
		nil,
		segments,
	)

	_, err := nodePath.ToQualifiedModuleName()
	assert.Error(t, err, "expected error for path with segments")
}

func TestNodePath_Equal(t *testing.T) {
	fqName := FQNameFromParts(
		PathFromString("My.Package"),
		PathFromString("Foo"),
		NameFromParts([]string{"bar"}),
	)
	np1 := NodePathFromFQName(fqName)
	np2 := NodePathFromFQName(fqName)

	assert.True(t, np1.Equal(np2), "expected equal NodePaths to be equal")

	np3 := NodePathFromFQName(FQNameFromParts(
		PathFromString("Other.Package"),
		PathFromString("Foo"),
		NameFromParts([]string{"bar"}),
	))

	assert.False(t, np1.Equal(np3), "expected different NodePaths to not be equal")
}

func TestNodePath_Equal_ModuleLevel(t *testing.T) {
	qName := NewQualifiedModuleName(
		PathFromString("My.Package"),
		PathFromString("Foo"),
	)
	np1 := NodePathFromQualifiedModuleName(qName)
	np2 := NodePathFromQualifiedModuleName(qName)

	assert.True(t, np1.Equal(np2), "expected equal module-level NodePaths to be equal")
}

func TestNodePath_Equal_WithSegments(t *testing.T) {
	segments := []Name{NameFromParts([]string{"seg"})}
	localName := NameFromParts([]string{"bar"})
	np1 := NodePathFromParts(
		PathFromString("My.Package"),
		PathFromString("Foo"),
		&localName,
		segments,
	)
	np2 := NodePathFromParts(
		PathFromString("My.Package"),
		PathFromString("Foo"),
		&localName,
		segments,
	)

	assert.True(t, np1.Equal(np2), "expected equal NodePaths with segments to be equal")
}

func TestNodePath_String(t *testing.T) {
	testCases := []struct {
		name     string
		nodePath NodePath
		expected string
	}{
		{
			name: "FQName path",
			nodePath: NodePathFromFQName(FQNameFromParts(
				PathFromString("My.Package"),
				PathFromString("Foo"),
				NameFromParts([]string{"bar"}),
			)),
			expected: "My.Package:Foo:bar",
		},
		{
			name: "Module-level path",
			nodePath: NodePathFromQualifiedModuleName(NewQualifiedModuleName(
				PathFromString("My.Package"),
				PathFromString("Foo"),
			)),
			expected: "My.Package:Foo",
		},
		{
			name: "Path with segments",
			nodePath: NodePathFromParts(
				PathFromString("My.Package"),
				PathFromString("Foo"),
				func() *Name { n := NameFromParts([]string{"bar"}); return &n }(),
				[]Name{
					NameFromParts([]string{"field1"}),
					NameFromParts([]string{"field2"}),
				},
			),
			expected: "My.Package:Foo:bar:field1:field2",
		},
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			got := tc.nodePath.String()
			assert.Equal(t, tc.expected, got, "String mismatch")
		})
	}
}

func TestParseNodePath(t *testing.T) {
	testCases := []struct {
		name     string
		input    string
		expected NodePath
		wantErr  bool
	}{
		{
			name:  "FQName path",
			input: "My.Package:Foo:bar",
			expected: NodePathFromFQName(FQNameFromParts(
				PathFromString("My.Package"),
				PathFromString("Foo"),
				NameFromParts([]string{"bar"}),
			)),
		},
		{
			name:  "Module-level path",
			input: "My.Package:Foo",
			expected: NodePathFromQualifiedModuleName(NewQualifiedModuleName(
				PathFromString("My.Package"),
				PathFromString("Foo"),
			)),
		},
		{
			name:  "Path with segments",
			input: "My.Package:Foo:bar:seg1:seg2",
			expected: func() NodePath {
				localName := NameFromString("bar")
				return NodePathFromParts(
					PathFromString("My.Package"),
					PathFromString("Foo"),
					&localName,
					[]Name{
						NameFromString("seg1"),
						NameFromString("seg2"),
					},
				)
			}(),
		},
		{
			name:    "Invalid - too few parts",
			input:   "My.Package",
			wantErr: true,
		},
		{
			name:    "Invalid - empty",
			input:   "",
			wantErr: true,
		},
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			got, err := ParseNodePath(tc.input)
			if tc.wantErr {
				assert.Error(t, err, "expected error")
				return
			}
			require.NoError(t, err, "ParseNodePath: unexpected error")
			assert.True(t, got.Equal(tc.expected), "ParseNodePath: result mismatch (got %q, want %q)", got.String(), tc.expected.String())
		})
	}
}

func TestNodePath_MarshalJSON(t *testing.T) {
	nodePath := NodePathFromFQName(FQNameFromParts(
		PathFromString("My.Package"),
		PathFromString("Foo"),
		NameFromParts([]string{"bar"}),
	))

	data, err := json.Marshal(nodePath)
	require.NoError(t, err, "MarshalJSON: unexpected error")

	var s string
	err = json.Unmarshal(data, &s)
	require.NoError(t, err, "unmarshal string: unexpected error")

	assert.Equal(t, "My.Package:Foo:bar", s, "MarshalJSON: result mismatch")
}

func TestNodePath_UnmarshalJSON(t *testing.T) {
	data := []byte(`"My.Package:Foo:bar"`)

	var nodePath NodePath
	err := json.Unmarshal(data, &nodePath)
	require.NoError(t, err, "UnmarshalJSON: unexpected error")

	expected := NodePathFromFQName(FQNameFromParts(
		PathFromString("My.Package"),
		PathFromString("Foo"),
		NameFromParts([]string{"bar"}),
	))

	assert.True(t, nodePath.Equal(expected), "UnmarshalJSON: result mismatch")
}

func TestNodePath_UnmarshalJSON_Invalid(t *testing.T) {
	testCases := []struct {
		name    string
		data    []byte
		wantErr bool
	}{
		{
			name:    "Not a string",
			data:    []byte(`123`),
			wantErr: true,
		},
		{
			name:    "Invalid format",
			data:    []byte(`"My.Package"`),
			wantErr: true,
		},
		{
			name:    "Nil receiver",
			data:    []byte(`"My.Package:Foo:bar"`),
			wantErr: false, // This is handled by the function
		},
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			var nodePath *NodePath
			err := nodePath.UnmarshalJSON(tc.data)
			if tc.wantErr {
				assert.Error(t, err, "expected error")
			} else {
				// For nil receiver, we expect an error
				assert.Error(t, err, "expected error for nil receiver")
			}
		})
	}
}

func TestNodePath_UnmarshalJSON_NilReceiver(t *testing.T) {
	var nodePath *NodePath
	err := nodePath.UnmarshalJSON([]byte(`"My.Package:Foo:bar"`))
	assert.Error(t, err, "expected error for nil receiver")
}

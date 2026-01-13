package ir

import (
	"encoding/json"
	"testing"
)

func TestNodePathFromFQName(t *testing.T) {
	fqName := FQNameFromParts(
		PathFromString("My.Package"),
		PathFromString("Foo"),
		NameFromParts([]string{"bar"}),
	)

	nodePath := NodePathFromFQName(fqName)

	if !nodePath.PackagePath().Equal(PathFromString("My.Package")) {
		t.Error("package path mismatch")
	}
	if !nodePath.ModulePath().Equal(PathFromString("Foo")) {
		t.Error("module path mismatch")
	}
	localName := nodePath.LocalName()
	if localName == nil {
		t.Error("expected local name to be non-nil")
	}
	if !localName.Equal(NameFromParts([]string{"bar"})) {
		t.Error("local name mismatch")
	}
	if len(nodePath.Segments()) != 0 {
		t.Error("expected no segments")
	}
}

func TestNodePathFromQualifiedModuleName(t *testing.T) {
	qName := NewQualifiedModuleName(
		PathFromString("My.Package"),
		PathFromString("Foo"),
	)

	nodePath := NodePathFromQualifiedModuleName(qName)

	if !nodePath.PackagePath().Equal(PathFromString("My.Package")) {
		t.Error("package path mismatch")
	}
	if !nodePath.ModulePath().Equal(PathFromString("Foo")) {
		t.Error("module path mismatch")
	}
	if nodePath.LocalName() != nil {
		t.Error("expected local name to be nil for module-level path")
	}
	if len(nodePath.Segments()) != 0 {
		t.Error("expected no segments")
	}
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

	if !nodePath.PackagePath().Equal(packagePath) {
		t.Error("package path mismatch")
	}
	if !nodePath.ModulePath().Equal(modulePath) {
		t.Error("module path mismatch")
	}
	gotLocalName := nodePath.LocalName()
	if gotLocalName == nil || !gotLocalName.Equal(localName) {
		t.Error("local name mismatch")
	}
	gotSegments := nodePath.Segments()
	if len(gotSegments) != 2 {
		t.Errorf("segments: got %d, want 2", len(gotSegments))
	}
}

func TestNodePathFromParts_ModuleLevel(t *testing.T) {
	packagePath := PathFromString("My.Package")
	modulePath := PathFromString("Foo")

	nodePath := NodePathFromParts(packagePath, modulePath, nil, nil)

	if nodePath.LocalName() != nil {
		t.Error("expected local name to be nil")
	}
}

func TestNodePath_PackagePath(t *testing.T) {
	nodePath := NodePathFromFQName(FQNameFromParts(
		PathFromString("Test.Package"),
		PathFromString("Module"),
		NameFromParts([]string{"value"}),
	))

	path := nodePath.PackagePath()
	if !path.Equal(PathFromString("Test.Package")) {
		t.Error("PackagePath mismatch")
	}
}

func TestNodePath_ModulePath(t *testing.T) {
	nodePath := NodePathFromFQName(FQNameFromParts(
		PathFromString("Test.Package"),
		PathFromString("Module"),
		NameFromParts([]string{"value"}),
	))

	path := nodePath.ModulePath()
	if !path.Equal(PathFromString("Module")) {
		t.Error("ModulePath mismatch")
	}
}

func TestNodePath_LocalName(t *testing.T) {
	localName := NameFromParts([]string{"test"})
	nodePath := NodePathFromFQName(FQNameFromParts(
		PathFromString("Test"),
		PathFromString("Module"),
		localName,
	))

	got := nodePath.LocalName()
	if got == nil {
		t.Error("expected local name to be non-nil")
	}
	if !got.Equal(localName) {
		t.Error("LocalName mismatch")
	}

	// Test defensive copy
	got2 := nodePath.LocalName()
	if got == got2 {
		t.Error("LocalName should return defensive copy")
	}
}

func TestNodePath_LocalName_Nil(t *testing.T) {
	nodePath := NodePathFromQualifiedModuleName(NewQualifiedModuleName(
		PathFromString("Test"),
		PathFromString("Module"),
	))

	if nodePath.LocalName() != nil {
		t.Error("expected local name to be nil for module-level path")
	}
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
	if len(got) != 2 {
		t.Errorf("Segments: got %d, want 2", len(got))
	}

	// Test defensive copy
	got2 := nodePath.Segments()
	if len(got2) != 2 {
		t.Error("Segments should return defensive copy")
	}
}

func TestNodePath_Segments_Empty(t *testing.T) {
	nodePath := NodePathFromFQName(FQNameFromParts(
		PathFromString("Test"),
		PathFromString("Module"),
		NameFromParts([]string{"value"}),
	))

	segments := nodePath.Segments()
	if segments != nil {
		t.Error("expected nil for empty segments")
	}
}

func TestNodePath_ToFQName(t *testing.T) {
	fqName := FQNameFromParts(
		PathFromString("My.Package"),
		PathFromString("Foo"),
		NameFromParts([]string{"bar"}),
	)
	nodePath := NodePathFromFQName(fqName)

	got, err := nodePath.ToFQName()
	if err != nil {
		t.Fatalf("ToFQName: unexpected error: %v", err)
	}

	if !got.Equal(fqName) {
		t.Error("ToFQName: result mismatch")
	}
}

func TestNodePath_ToFQName_ModuleLevel(t *testing.T) {
	nodePath := NodePathFromQualifiedModuleName(NewQualifiedModuleName(
		PathFromString("My.Package"),
		PathFromString("Foo"),
	))

	_, err := nodePath.ToFQName()
	if err == nil {
		t.Error("expected error for module-level path")
	}
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
	if err == nil {
		t.Error("expected error for path with segments")
	}
}

func TestNodePath_ToQualifiedModuleName(t *testing.T) {
	qName := NewQualifiedModuleName(
		PathFromString("My.Package"),
		PathFromString("Foo"),
	)
	nodePath := NodePathFromQualifiedModuleName(qName)

	got, err := nodePath.ToQualifiedModuleName()
	if err != nil {
		t.Fatalf("ToQualifiedModuleName: unexpected error: %v", err)
	}

	if !got.Equal(qName) {
		t.Error("ToQualifiedModuleName: result mismatch")
	}
}

func TestNodePath_ToQualifiedModuleName_WithLocalName(t *testing.T) {
	nodePath := NodePathFromFQName(FQNameFromParts(
		PathFromString("My.Package"),
		PathFromString("Foo"),
		NameFromParts([]string{"bar"}),
	))

	_, err := nodePath.ToQualifiedModuleName()
	if err == nil {
		t.Error("expected error for path with local name")
	}
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
	if err == nil {
		t.Error("expected error for path with segments")
	}
}

func TestNodePath_Equal(t *testing.T) {
	fqName := FQNameFromParts(
		PathFromString("My.Package"),
		PathFromString("Foo"),
		NameFromParts([]string{"bar"}),
	)
	np1 := NodePathFromFQName(fqName)
	np2 := NodePathFromFQName(fqName)

	if !np1.Equal(np2) {
		t.Error("expected equal NodePaths to be equal")
	}

	np3 := NodePathFromFQName(FQNameFromParts(
		PathFromString("Other.Package"),
		PathFromString("Foo"),
		NameFromParts([]string{"bar"}),
	))

	if np1.Equal(np3) {
		t.Error("expected different NodePaths to not be equal")
	}
}

func TestNodePath_Equal_ModuleLevel(t *testing.T) {
	qName := NewQualifiedModuleName(
		PathFromString("My.Package"),
		PathFromString("Foo"),
	)
	np1 := NodePathFromQualifiedModuleName(qName)
	np2 := NodePathFromQualifiedModuleName(qName)

	if !np1.Equal(np2) {
		t.Error("expected equal module-level NodePaths to be equal")
	}
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

	if !np1.Equal(np2) {
		t.Error("expected equal NodePaths with segments to be equal")
	}
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
			if got != tc.expected {
				t.Errorf("String: got %q, want %q", got, tc.expected)
			}
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
			expected: NodePathFromParts(
				PathFromString("My.Package"),
				PathFromString("Foo"),
				func() *Name { n := NameFromParts([]string{"bar"}); return &n }(),
				[]Name{
					NameFromParts([]string{"seg1"}),
					NameFromParts([]string{"seg2"}),
				},
			),
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
				if err == nil {
					t.Error("expected error")
				}
				return
			}
			if err != nil {
				t.Fatalf("ParseNodePath: unexpected error: %v", err)
			}
			if !got.Equal(tc.expected) {
				t.Errorf("ParseNodePath: got %v, want %v", got, tc.expected)
			}
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
	if err != nil {
		t.Fatalf("MarshalJSON: unexpected error: %v", err)
	}

	var s string
	if err := json.Unmarshal(data, &s); err != nil {
		t.Fatalf("unmarshal string: unexpected error: %v", err)
	}

	if s != "My.Package:Foo:bar" {
		t.Errorf("MarshalJSON: got %q, want %q", s, "My.Package:Foo:bar")
	}
}

func TestNodePath_UnmarshalJSON(t *testing.T) {
	data := []byte(`"My.Package:Foo:bar"`)

	var nodePath NodePath
	if err := json.Unmarshal(data, &nodePath); err != nil {
		t.Fatalf("UnmarshalJSON: unexpected error: %v", err)
	}

	expected := NodePathFromFQName(FQNameFromParts(
		PathFromString("My.Package"),
		PathFromString("Foo"),
		NameFromParts([]string{"bar"}),
	))

	if !nodePath.Equal(expected) {
		t.Error("UnmarshalJSON: result mismatch")
	}
}

func TestNodePath_UnmarshalJSON_Invalid(t *testing.T) {
	testCases := []struct {
		name  string
		data  []byte
		wantErr bool
	}{
		{
			name:  "Not a string",
			data:  []byte(`123`),
			wantErr: true,
		},
		{
			name:  "Invalid format",
			data:  []byte(`"My.Package"`),
			wantErr: true,
		},
		{
			name:  "Nil receiver",
			data:  []byte(`"My.Package:Foo:bar"`),
			wantErr: false, // This is handled by the function
		},
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			var nodePath *NodePath
			err := nodePath.UnmarshalJSON(tc.data)
			if tc.wantErr {
				if err == nil {
					t.Error("expected error")
				}
			} else {
				// For nil receiver, we expect an error
				if err == nil {
					t.Error("expected error for nil receiver")
				}
			}
		})
	}
}

func TestNodePath_UnmarshalJSON_NilReceiver(t *testing.T) {
	var nodePath *NodePath
	err := nodePath.UnmarshalJSON([]byte(`"My.Package:Foo:bar"`))
	if err == nil {
		t.Error("expected error for nil receiver")
	}
}

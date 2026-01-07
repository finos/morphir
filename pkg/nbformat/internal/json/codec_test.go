package json

import (
	"encoding/json"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestMultilineStringUnmarshal(t *testing.T) {
	t.Run("unmarshal from string", func(t *testing.T) {
		var m MultilineString
		err := json.Unmarshal([]byte(`"hello\nworld"`), &m)
		require.NoError(t, err)
		assert.Equal(t, "hello\nworld", m.String())
	})

	t.Run("unmarshal from array", func(t *testing.T) {
		var m MultilineString
		err := json.Unmarshal([]byte(`["hello\n", "world"]`), &m)
		require.NoError(t, err)
		assert.Equal(t, "hello\nworld", m.String())
	})

	t.Run("unmarshal from empty array", func(t *testing.T) {
		var m MultilineString
		err := json.Unmarshal([]byte(`[]`), &m)
		require.NoError(t, err)
		assert.Equal(t, "", m.String())
	})

	t.Run("unmarshal from empty string", func(t *testing.T) {
		var m MultilineString
		err := json.Unmarshal([]byte(`""`), &m)
		require.NoError(t, err)
		assert.Equal(t, "", m.String())
	})
}

func TestMultilineStringMarshal(t *testing.T) {
	t.Run("marshal single line", func(t *testing.T) {
		m := MultilineString("hello")
		data, err := json.Marshal(m)
		require.NoError(t, err)
		assert.Equal(t, `["hello"]`, string(data))
	})

	t.Run("marshal multiple lines", func(t *testing.T) {
		m := MultilineString("line1\nline2\n")
		data, err := json.Marshal(m)
		require.NoError(t, err)
		assert.Equal(t, `["line1\n","line2\n"]`, string(data))
	})

	t.Run("marshal empty string", func(t *testing.T) {
		m := MultilineString("")
		data, err := json.Marshal(m)
		require.NoError(t, err)
		assert.Equal(t, `[]`, string(data))
	})

	t.Run("marshal trailing content without newline", func(t *testing.T) {
		m := MultilineString("line1\nline2")
		data, err := json.Marshal(m)
		require.NoError(t, err)
		assert.Equal(t, `["line1\n","line2"]`, string(data))
	})
}

func TestSplitLines(t *testing.T) {
	tests := []struct {
		name     string
		input    string
		expected []string
	}{
		{"empty", "", []string{}},
		{"single line no newline", "hello", []string{"hello"}},
		{"single line with newline", "hello\n", []string{"hello\n"}},
		{"multiple lines", "a\nb\nc\n", []string{"a\n", "b\n", "c\n"}},
		{"trailing content", "a\nb", []string{"a\n", "b"}},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := splitLines(tt.input)
			assert.Equal(t, tt.expected, result)
		})
	}
}

func TestMimeBundleJSON(t *testing.T) {
	t.Run("GetString from string value", func(t *testing.T) {
		m := MimeBundleJSON{"text/plain": "hello"}
		s, ok := m.GetString("text/plain")
		assert.True(t, ok)
		assert.Equal(t, "hello", s)
	})

	t.Run("GetString from array value", func(t *testing.T) {
		m := MimeBundleJSON{"text/plain": []any{"hello\n", "world"}}
		s, ok := m.GetString("text/plain")
		assert.True(t, ok)
		assert.Equal(t, "hello\nworld", s)
	})

	t.Run("GetString from string array", func(t *testing.T) {
		m := MimeBundleJSON{"text/plain": []string{"hello\n", "world"}}
		s, ok := m.GetString("text/plain")
		assert.True(t, ok)
		assert.Equal(t, "hello\nworld", s)
	})

	t.Run("GetString missing key", func(t *testing.T) {
		m := MimeBundleJSON{}
		s, ok := m.GetString("missing")
		assert.False(t, ok)
		assert.Equal(t, "", s)
	})

	t.Run("GetString non-string value", func(t *testing.T) {
		m := MimeBundleJSON{"number": 42}
		s, ok := m.GetString("number")
		assert.False(t, ok)
		assert.Equal(t, "", s)
	})
}

func TestParseScrolled(t *testing.T) {
	tests := []struct {
		name     string
		input    any
		expected int
	}{
		{"nil", nil, 0},
		{"true", true, 1},
		{"false", false, 2},
		{"auto string", "auto", 3},
		{"other string", "other", 0},
		{"number", 42, 0},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := ParseScrolled(tt.input)
			assert.Equal(t, tt.expected, result)
		})
	}
}

func TestParseMimeBundle(t *testing.T) {
	t.Run("nil input", func(t *testing.T) {
		result := ParseMimeBundle(nil)
		assert.Nil(t, result)
	})

	t.Run("converts array of strings to string", func(t *testing.T) {
		input := map[string]any{
			"text/plain": []any{"hello\n", "world"},
		}
		result := ParseMimeBundle(input)
		assert.Equal(t, "hello\nworld", result["text/plain"])
	})

	t.Run("preserves non-array values", func(t *testing.T) {
		input := map[string]any{
			"text/plain": "hello",
			"number":     42,
		}
		result := ParseMimeBundle(input)
		assert.Equal(t, "hello", result["text/plain"])
		assert.Equal(t, 42, result["number"])
	})
}

func TestNotebookJSONStruct(t *testing.T) {
	t.Run("unmarshal complete notebook", func(t *testing.T) {
		jsonStr := `{
			"nbformat": 4,
			"nbformat_minor": 5,
			"metadata": {
				"kernelspec": {
					"name": "python3",
					"display_name": "Python 3",
					"language": "python"
				}
			},
			"cells": [{
				"cell_type": "code",
				"id": "cell-1",
				"source": ["print('hello')"],
				"metadata": {},
				"execution_count": 1,
				"outputs": []
			}]
		}`

		var nb NotebookJSON
		err := json.Unmarshal([]byte(jsonStr), &nb)
		require.NoError(t, err)

		assert.Equal(t, 4, nb.NBFormat)
		assert.Equal(t, 5, nb.NBFormatMinor)
		require.NotNil(t, nb.Metadata.KernelSpec)
		assert.Equal(t, "python3", nb.Metadata.KernelSpec.Name)
		require.Len(t, nb.Cells, 1)
		assert.Equal(t, "code", nb.Cells[0].CellType)
		assert.Equal(t, "cell-1", nb.Cells[0].ID)
	})
}

func TestCellJSONStruct(t *testing.T) {
	t.Run("unmarshal code cell", func(t *testing.T) {
		jsonStr := `{
			"cell_type": "code",
			"id": "cell-1",
			"source": "x = 1",
			"metadata": {"scrolled": true},
			"execution_count": 5,
			"outputs": [
				{"output_type": "stream", "name": "stdout", "text": "hello"}
			]
		}`

		var cell CellJSON
		err := json.Unmarshal([]byte(jsonStr), &cell)
		require.NoError(t, err)

		assert.Equal(t, "code", cell.CellType)
		assert.Equal(t, "cell-1", cell.ID)
		assert.Equal(t, "x = 1", cell.Source.String())
		assert.Equal(t, true, cell.Metadata.Scrolled)
		require.NotNil(t, cell.ExecutionCount)
		assert.Equal(t, 5, *cell.ExecutionCount)
		require.Len(t, cell.Outputs, 1)
	})

	t.Run("unmarshal markdown cell with attachments", func(t *testing.T) {
		jsonStr := `{
			"cell_type": "markdown",
			"source": "# Title",
			"metadata": {},
			"attachments": {
				"image.png": {"image/png": "base64data"}
			}
		}`

		var cell CellJSON
		err := json.Unmarshal([]byte(jsonStr), &cell)
		require.NoError(t, err)

		assert.Equal(t, "markdown", cell.CellType)
		require.NotNil(t, cell.Attachments)
		assert.Contains(t, cell.Attachments, "image.png")
	})
}

func TestOutputJSONStruct(t *testing.T) {
	t.Run("unmarshal stream output", func(t *testing.T) {
		jsonStr := `{
			"output_type": "stream",
			"name": "stdout",
			"text": ["hello\n", "world"]
		}`

		var output OutputJSON
		err := json.Unmarshal([]byte(jsonStr), &output)
		require.NoError(t, err)

		assert.Equal(t, "stream", output.OutputType)
		assert.Equal(t, "stdout", output.Name)
		assert.Equal(t, "hello\nworld", output.Text.String())
	})

	t.Run("unmarshal error output", func(t *testing.T) {
		jsonStr := `{
			"output_type": "error",
			"ename": "ValueError",
			"evalue": "invalid value",
			"traceback": ["line1", "line2"]
		}`

		var output OutputJSON
		err := json.Unmarshal([]byte(jsonStr), &output)
		require.NoError(t, err)

		assert.Equal(t, "error", output.OutputType)
		assert.Equal(t, "ValueError", output.Ename)
		assert.Equal(t, "invalid value", output.Evalue)
		assert.Equal(t, []string{"line1", "line2"}, output.Traceback)
	})

	t.Run("unmarshal execute_result output", func(t *testing.T) {
		jsonStr := `{
			"output_type": "execute_result",
			"execution_count": 3,
			"data": {"text/plain": "42"},
			"metadata": {}
		}`

		var output OutputJSON
		err := json.Unmarshal([]byte(jsonStr), &output)
		require.NoError(t, err)

		assert.Equal(t, "execute_result", output.OutputType)
		require.NotNil(t, output.ExecutionCount)
		assert.Equal(t, 3, *output.ExecutionCount)
		assert.Equal(t, "42", output.Data["text/plain"])
	})
}

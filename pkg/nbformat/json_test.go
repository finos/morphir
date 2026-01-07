package nbformat

import (
	"bytes"
	"strings"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// Sample notebook JSON for testing
const sampleNotebookJSON = `{
 "cells": [
  {
   "cell_type": "markdown",
   "id": "cell-1",
   "metadata": {},
   "source": [
    "# Hello World\n",
    "\n",
    "This is a test notebook."
   ]
  },
  {
   "cell_type": "code",
   "execution_count": 1,
   "id": "cell-2",
   "metadata": {
    "scrolled": true
   },
   "outputs": [
    {
     "name": "stdout",
     "output_type": "stream",
     "text": [
      "Hello, World!\n"
     ]
    }
   ],
   "source": [
    "print('Hello, World!')"
   ]
  },
  {
   "cell_type": "code",
   "execution_count": 2,
   "id": "cell-3",
   "metadata": {},
   "outputs": [
    {
     "data": {
      "text/plain": [
       "42"
      ]
     },
     "execution_count": 2,
     "metadata": {},
     "output_type": "execute_result"
    }
   ],
   "source": [
    "6 * 7"
   ]
  },
  {
   "cell_type": "code",
   "execution_count": 3,
   "id": "cell-4",
   "metadata": {},
   "outputs": [
    {
     "ename": "ZeroDivisionError",
     "evalue": "division by zero",
     "output_type": "error",
     "traceback": [
      "Traceback (most recent call last):",
      "  File \"<stdin>\", line 1",
      "ZeroDivisionError: division by zero"
     ]
    }
   ],
   "source": [
    "1/0"
   ]
  },
  {
   "cell_type": "raw",
   "id": "cell-5",
   "metadata": {},
   "source": [
    "<html>\n",
    "<body>Raw content</body>\n",
    "</html>"
   ]
  }
 ],
 "metadata": {
  "kernelspec": {
   "display_name": "Python 3",
   "language": "python",
   "name": "python3"
  },
  "language_info": {
   "file_extension": ".py",
   "mimetype": "text/x-python",
   "name": "python",
   "version": "3.10.0"
  }
 },
 "nbformat": 4,
 "nbformat_minor": 5
}
`

func TestReadBytes(t *testing.T) {
	t.Run("reads sample notebook", func(t *testing.T) {
		nb, err := ReadBytes([]byte(sampleNotebookJSON))
		require.NoError(t, err)

		assert.Equal(t, 4, nb.NBFormat())
		assert.Equal(t, 5, nb.NBFormatMinor())
		assert.Equal(t, 5, nb.CellCount())
	})

	t.Run("reads metadata", func(t *testing.T) {
		nb, err := ReadBytes([]byte(sampleNotebookJSON))
		require.NoError(t, err)

		meta := nb.Metadata()
		require.NotNil(t, meta.KernelSpec())
		assert.Equal(t, "python3", meta.KernelSpec().Name())
		assert.Equal(t, "Python 3", meta.KernelSpec().DisplayName())
		assert.Equal(t, "python", meta.KernelSpec().Language())

		require.NotNil(t, meta.LanguageInfo())
		assert.Equal(t, "python", meta.LanguageInfo().Name())
		assert.Equal(t, "3.10.0", meta.LanguageInfo().Version())
		assert.Equal(t, ".py", meta.LanguageInfo().FileExtension())
	})

	t.Run("reads markdown cell", func(t *testing.T) {
		nb, err := ReadBytes([]byte(sampleNotebookJSON))
		require.NoError(t, err)

		cell := nb.Cell(0)
		assert.Equal(t, CellTypeMarkdown, cell.CellType())
		assert.Equal(t, "cell-1", cell.ID())
		assert.Contains(t, cell.Source(), "# Hello World")
	})

	t.Run("reads code cell with stream output", func(t *testing.T) {
		nb, err := ReadBytes([]byte(sampleNotebookJSON))
		require.NoError(t, err)

		cell := nb.Cell(1)
		assert.Equal(t, CellTypeCode, cell.CellType())
		assert.Equal(t, "cell-2", cell.ID())
		assert.Contains(t, cell.Source(), "print")

		code := cell.(CodeCell)
		require.NotNil(t, code.ExecutionCount())
		assert.Equal(t, 1, *code.ExecutionCount())

		outputs := code.Outputs()
		require.Len(t, outputs, 1)

		stream, ok := outputs[0].(StreamOutput)
		require.True(t, ok)
		assert.Equal(t, StreamStdout, stream.Name())
		assert.Contains(t, stream.Text(), "Hello, World!")
	})

	t.Run("reads code cell with execute_result output", func(t *testing.T) {
		nb, err := ReadBytes([]byte(sampleNotebookJSON))
		require.NoError(t, err)

		cell := nb.Cell(2)
		code := cell.(CodeCell)

		outputs := code.Outputs()
		require.Len(t, outputs, 1)

		result, ok := outputs[0].(ExecuteResultOutput)
		require.True(t, ok)
		assert.Equal(t, 2, result.ExecutionCount())

		val, ok := result.Data().Get("text/plain")
		assert.True(t, ok)
		assert.Equal(t, "42", val)
	})

	t.Run("reads code cell with error output", func(t *testing.T) {
		nb, err := ReadBytes([]byte(sampleNotebookJSON))
		require.NoError(t, err)

		cell := nb.Cell(3)
		code := cell.(CodeCell)

		outputs := code.Outputs()
		require.Len(t, outputs, 1)

		errOut, ok := outputs[0].(ErrorOutput)
		require.True(t, ok)
		assert.Equal(t, "ZeroDivisionError", errOut.Ename())
		assert.Equal(t, "division by zero", errOut.Evalue())
		assert.Len(t, errOut.Traceback(), 3)
	})

	t.Run("reads raw cell", func(t *testing.T) {
		nb, err := ReadBytes([]byte(sampleNotebookJSON))
		require.NoError(t, err)

		cell := nb.Cell(4)
		assert.Equal(t, CellTypeRaw, cell.CellType())
		assert.Equal(t, "cell-5", cell.ID())
		assert.Contains(t, cell.Source(), "<html>")
	})

	t.Run("reads cell metadata scrolled", func(t *testing.T) {
		nb, err := ReadBytes([]byte(sampleNotebookJSON))
		require.NoError(t, err)

		cell := nb.Cell(1)
		assert.Equal(t, ScrolledTrue, cell.Metadata().Scrolled())
	})
}

func TestRead(t *testing.T) {
	t.Run("reads from reader", func(t *testing.T) {
		r := strings.NewReader(sampleNotebookJSON)
		nb, err := Read(r)
		require.NoError(t, err)

		assert.Equal(t, 4, nb.NBFormat())
		assert.Equal(t, 5, nb.CellCount())
	})
}

func TestWriteBytes(t *testing.T) {
	t.Run("writes notebook to bytes", func(t *testing.T) {
		nb := NewNotebookBuilder().
			WithKernelSpec("python3", "Python 3").
			AddMarkdownCell("# Title").
			AddCodeCell("x = 1").
			Build()

		data, err := WriteBytes(nb)
		require.NoError(t, err)

		assert.Contains(t, string(data), `"nbformat": 4`)
		assert.Contains(t, string(data), `"cell_type": "markdown"`)
		assert.Contains(t, string(data), `"cell_type": "code"`)
	})
}

func TestWrite(t *testing.T) {
	t.Run("writes notebook to writer", func(t *testing.T) {
		nb := NewNotebookBuilder().
			AddCodeCell("print('hello')").
			Build()

		var buf bytes.Buffer
		err := Write(nb, &buf)
		require.NoError(t, err)

		assert.Contains(t, buf.String(), `"nbformat"`)
		assert.Contains(t, buf.String(), `print('hello')`)
	})
}

func TestRoundTrip(t *testing.T) {
	t.Run("read-write-read produces equivalent notebook", func(t *testing.T) {
		// Read original
		nb1, err := ReadBytes([]byte(sampleNotebookJSON))
		require.NoError(t, err)

		// Write
		data, err := WriteBytes(nb1)
		require.NoError(t, err)

		// Read again
		nb2, err := ReadBytes(data)
		require.NoError(t, err)

		// Compare
		assert.Equal(t, nb1.NBFormat(), nb2.NBFormat())
		assert.Equal(t, nb1.NBFormatMinor(), nb2.NBFormatMinor())
		assert.Equal(t, nb1.CellCount(), nb2.CellCount())

		for i := 0; i < nb1.CellCount(); i++ {
			c1 := nb1.Cell(i)
			c2 := nb2.Cell(i)
			assert.Equal(t, c1.CellType(), c2.CellType())
			assert.Equal(t, c1.ID(), c2.ID())
			assert.Equal(t, c1.Source(), c2.Source())
		}
	})

	t.Run("roundtrip preserves code cell outputs", func(t *testing.T) {
		nb1, err := ReadBytes([]byte(sampleNotebookJSON))
		require.NoError(t, err)

		data, err := WriteBytes(nb1)
		require.NoError(t, err)

		nb2, err := ReadBytes(data)
		require.NoError(t, err)

		// Check code cell with stream output
		code1 := nb1.Cell(1).(CodeCell)
		code2 := nb2.Cell(1).(CodeCell)

		assert.Equal(t, *code1.ExecutionCount(), *code2.ExecutionCount())
		require.Len(t, code2.Outputs(), len(code1.Outputs()))

		stream1 := code1.Outputs()[0].(StreamOutput)
		stream2 := code2.Outputs()[0].(StreamOutput)
		assert.Equal(t, stream1.Name(), stream2.Name())
		assert.Equal(t, stream1.Text(), stream2.Text())
	})

	t.Run("roundtrip preserves error outputs", func(t *testing.T) {
		nb1, err := ReadBytes([]byte(sampleNotebookJSON))
		require.NoError(t, err)

		data, err := WriteBytes(nb1)
		require.NoError(t, err)

		nb2, err := ReadBytes(data)
		require.NoError(t, err)

		code1 := nb1.Cell(3).(CodeCell)
		code2 := nb2.Cell(3).(CodeCell)

		err1 := code1.Outputs()[0].(ErrorOutput)
		err2 := code2.Outputs()[0].(ErrorOutput)

		assert.Equal(t, err1.Ename(), err2.Ename())
		assert.Equal(t, err1.Evalue(), err2.Evalue())
		assert.Equal(t, err1.Traceback(), err2.Traceback())
	})
}

func TestWriteWithOptions(t *testing.T) {
	t.Run("respects indent option", func(t *testing.T) {
		nb := NewNotebookBuilder().
			AddCodeCell("x = 1").
			Build()

		// Default (single space)
		data1, err := WriteBytesWithOptions(nb, WriteOptions{Indent: " "})
		require.NoError(t, err)

		// Two spaces
		data2, err := WriteBytesWithOptions(nb, WriteOptions{Indent: "  "})
		require.NoError(t, err)

		// Two-space indent should be longer
		assert.Greater(t, len(data2), len(data1))
	})
}

func TestReadInvalidJSON(t *testing.T) {
	t.Run("returns error for invalid JSON", func(t *testing.T) {
		_, err := ReadBytes([]byte("not valid json"))
		assert.Error(t, err)
	})

	t.Run("returns error for empty input", func(t *testing.T) {
		_, err := ReadBytes([]byte(""))
		assert.Error(t, err)
	})
}

func TestMinimalNotebook(t *testing.T) {
	t.Run("reads minimal notebook", func(t *testing.T) {
		minimal := `{"nbformat": 4, "nbformat_minor": 5, "metadata": {}, "cells": []}`

		nb, err := ReadBytes([]byte(minimal))
		require.NoError(t, err)

		assert.Equal(t, 4, nb.NBFormat())
		assert.Equal(t, 5, nb.NBFormatMinor())
		assert.Equal(t, 0, nb.CellCount())
	})
}

func TestSourceAsString(t *testing.T) {
	t.Run("reads source as string", func(t *testing.T) {
		jsonStr := `{
			"nbformat": 4,
			"nbformat_minor": 5,
			"metadata": {},
			"cells": [{
				"cell_type": "code",
				"metadata": {},
				"source": "x = 1\ny = 2"
			}]
		}`

		nb, err := ReadBytes([]byte(jsonStr))
		require.NoError(t, err)

		assert.Equal(t, "x = 1\ny = 2", nb.Cell(0).Source())
	})
}

func TestReadDisplayDataOutput(t *testing.T) {
	t.Run("reads display_data output", func(t *testing.T) {
		jsonStr := `{
			"nbformat": 4,
			"nbformat_minor": 5,
			"metadata": {},
			"cells": [{
				"cell_type": "code",
				"metadata": {},
				"source": "",
				"outputs": [{
					"output_type": "display_data",
					"data": {
						"text/plain": ["<Figure>"],
						"image/png": "iVBORw0KGgo="
					},
					"metadata": {}
				}]
			}]
		}`

		nb, err := ReadBytes([]byte(jsonStr))
		require.NoError(t, err)

		code := nb.Cell(0).(CodeCell)
		require.Len(t, code.Outputs(), 1)

		display, ok := code.Outputs()[0].(DisplayDataOutput)
		require.True(t, ok)

		textVal, ok := display.Data().Get("text/plain")
		assert.True(t, ok)
		assert.Equal(t, "<Figure>", textVal)

		pngVal, ok := display.Data().Get("image/png")
		assert.True(t, ok)
		assert.Equal(t, "iVBORw0KGgo=", pngVal)
	})
}

func TestCellAttachments(t *testing.T) {
	t.Run("reads cell attachments", func(t *testing.T) {
		jsonStr := `{
			"nbformat": 4,
			"nbformat_minor": 5,
			"metadata": {},
			"cells": [{
				"cell_type": "markdown",
				"metadata": {},
				"source": "![image](attachment:image.png)",
				"attachments": {
					"image.png": {
						"image/png": "iVBORw0KGgo="
					}
				}
			}]
		}`

		nb, err := ReadBytes([]byte(jsonStr))
		require.NoError(t, err)

		md := nb.Cell(0).(MarkdownCell)
		attachments := md.Attachments()
		require.Contains(t, attachments, "image.png")

		val, ok := attachments["image.png"].Get("image/png")
		assert.True(t, ok)
		assert.Equal(t, "iVBORw0KGgo=", val)
	})
}

func TestScrolledStates(t *testing.T) {
	tests := []struct {
		name     string
		json     string
		expected ScrolledState
	}{
		{
			name:     "scrolled true",
			json:     `{"cell_type": "code", "metadata": {"scrolled": true}, "source": ""}`,
			expected: ScrolledTrue,
		},
		{
			name:     "scrolled false",
			json:     `{"cell_type": "code", "metadata": {"scrolled": false}, "source": ""}`,
			expected: ScrolledFalse,
		},
		{
			name:     "scrolled auto",
			json:     `{"cell_type": "code", "metadata": {"scrolled": "auto"}, "source": ""}`,
			expected: ScrolledAuto,
		},
		{
			name:     "scrolled unset",
			json:     `{"cell_type": "code", "metadata": {}, "source": ""}`,
			expected: ScrolledUnset,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			jsonStr := `{"nbformat": 4, "nbformat_minor": 5, "metadata": {}, "cells": [` + tt.json + `]}`
			nb, err := ReadBytes([]byte(jsonStr))
			require.NoError(t, err)

			assert.Equal(t, tt.expected, nb.Cell(0).Metadata().Scrolled())
		})
	}
}

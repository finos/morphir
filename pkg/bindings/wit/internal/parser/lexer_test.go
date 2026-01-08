package parser

import (
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestLexerPunctuation(t *testing.T) {
	tests := []struct {
		input    string
		expected TokenKind
	}{
		{"(", TokenLParen},
		{")", TokenRParen},
		{"{", TokenLBrace},
		{"}", TokenRBrace},
		{"<", TokenLAngle},
		{">", TokenRAngle},
		{",", TokenComma},
		{":", TokenColon},
		{";", TokenSemicolon},
		{"=", TokenEqual},
		{"*", TokenStar},
		{".", TokenDot},
		{"@", TokenAt},
		{"%", TokenPercent},
		{"/", TokenSlash},
		{"->", TokenArrow},
	}

	for _, tt := range tests {
		t.Run(tt.input, func(t *testing.T) {
			lexer := NewLexer(tt.input)
			tok := lexer.NextToken()
			assert.Equal(t, tt.expected, tok.Kind)
		})
	}
}

func TestLexerKeywords(t *testing.T) {
	tests := []struct {
		input    string
		expected TokenKind
	}{
		{"package", TokenPackage},
		{"interface", TokenInterface},
		{"world", TokenWorld},
		{"func", TokenFunc},
		{"type", TokenType},
		{"record", TokenRecord},
		{"variant", TokenVariant},
		{"enum", TokenEnum},
		{"flags", TokenFlags},
		{"resource", TokenResource},
		{"use", TokenUse},
		{"as", TokenAs},
		{"import", TokenImport},
		{"export", TokenExport},
		{"include", TokenInclude},
		{"with", TokenWith},
		{"constructor", TokenConstructor},
		{"static", TokenStatic},
		{"async", TokenAsync},
		{"own", TokenOwn},
		{"borrow", TokenBorrow},
	}

	for _, tt := range tests {
		t.Run(tt.input, func(t *testing.T) {
			lexer := NewLexer(tt.input)
			tok := lexer.NextToken()
			assert.Equal(t, tt.expected, tok.Kind)
			assert.Equal(t, tt.input, tok.Value)
		})
	}
}

func TestLexerBuiltinTypes(t *testing.T) {
	tests := []struct {
		input    string
		expected TokenKind
	}{
		{"u8", TokenU8},
		{"u16", TokenU16},
		{"u32", TokenU32},
		{"u64", TokenU64},
		{"s8", TokenS8},
		{"s16", TokenS16},
		{"s32", TokenS32},
		{"s64", TokenS64},
		{"f32", TokenF32},
		{"f64", TokenF64},
		{"bool", TokenBool},
		{"char", TokenChar},
		{"string", TokenString},
		{"list", TokenList},
		{"option", TokenOption},
		{"result", TokenResult},
		{"tuple", TokenTuple},
		{"future", TokenFuture},
		{"stream", TokenStream},
	}

	for _, tt := range tests {
		t.Run(tt.input, func(t *testing.T) {
			lexer := NewLexer(tt.input)
			tok := lexer.NextToken()
			assert.Equal(t, tt.expected, tok.Kind)
			assert.Equal(t, tt.input, tok.Value)
		})
	}
}

func TestLexerIdentifiers(t *testing.T) {
	tests := []struct {
		input    string
		expected string
	}{
		{"foo", "foo"},
		{"foo-bar", "foo-bar"},
		{"my-type", "my-type"},
		{"get-random-bytes", "get-random-bytes"},
		{"wall-clock", "wall-clock"},
	}

	for _, tt := range tests {
		t.Run(tt.input, func(t *testing.T) {
			lexer := NewLexer(tt.input)
			tok := lexer.NextToken()
			assert.Equal(t, TokenIdent, tok.Kind)
			assert.Equal(t, tt.expected, tok.Value)
		})
	}
}

func TestLexerIntegers(t *testing.T) {
	tests := []struct {
		input    string
		expected string
	}{
		{"0", "0"},
		{"1", "1"},
		{"123", "123"},
		{"999999", "999999"},
	}

	for _, tt := range tests {
		t.Run(tt.input, func(t *testing.T) {
			lexer := NewLexer(tt.input)
			tok := lexer.NextToken()
			assert.Equal(t, TokenInteger, tok.Kind)
			assert.Equal(t, tt.expected, tok.Value)
		})
	}
}

func TestLexerComments(t *testing.T) {
	tests := []struct {
		name     string
		input    string
		expected TokenKind
	}{
		{
			name:     "line comment then identifier",
			input:    "// comment\nfoo",
			expected: TokenIdent,
		},
		{
			name:     "block comment then identifier",
			input:    "/* comment */foo",
			expected: TokenIdent,
		},
		{
			name:     "nested block comment",
			input:    "/* outer /* inner */ outer */bar",
			expected: TokenIdent,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			lexer := NewLexer(tt.input)
			tok := lexer.NextToken()
			assert.Equal(t, tt.expected, tok.Kind)
		})
	}
}

func TestLexerWhitespace(t *testing.T) {
	input := "  \t\n\r  foo  \n  bar"
	lexer := NewLexer(input)

	tok1 := lexer.NextToken()
	assert.Equal(t, TokenIdent, tok1.Kind)
	assert.Equal(t, "foo", tok1.Value)

	tok2 := lexer.NextToken()
	assert.Equal(t, TokenIdent, tok2.Kind)
	assert.Equal(t, "bar", tok2.Value)

	tok3 := lexer.NextToken()
	assert.Equal(t, TokenEOF, tok3.Kind)
}

func TestLexerPositions(t *testing.T) {
	input := "foo\nbar"
	lexer := NewLexer(input)

	tok1 := lexer.NextToken()
	assert.Equal(t, 1, tok1.Pos.Line)
	assert.Equal(t, 1, tok1.Pos.Column)

	tok2 := lexer.NextToken()
	assert.Equal(t, 2, tok2.Pos.Line)
	assert.Equal(t, 1, tok2.Pos.Column)
}

func TestLexerFullPackage(t *testing.T) {
	input := `package wasi:clocks@0.2.0;

interface wall-clock {
    record datetime {
        seconds: u64,
    }
    now: func() -> datetime;
}`

	lexer := NewLexer(input)
	tokens := lexer.Tokenize()

	// Just verify we got tokens and no errors
	require.NotEmpty(t, tokens)

	// Find the EOF token
	lastToken := tokens[len(tokens)-1]
	assert.Equal(t, TokenEOF, lastToken.Kind, "should end with EOF")

	// Verify package token is first
	assert.Equal(t, TokenPackage, tokens[0].Kind)
}

func TestLexerUnderscore(t *testing.T) {
	tests := []struct {
		name   string
		input  string
		tokens []TokenKind
	}{
		{
			name:   "standalone underscore",
			input:  "_",
			tokens: []TokenKind{TokenUnderscore, TokenEOF},
		},
		{
			name:   "underscore in result type",
			input:  "result<_, error>",
			tokens: []TokenKind{TokenResult, TokenLAngle, TokenUnderscore, TokenComma, TokenIdent, TokenRAngle, TokenEOF},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			lexer := NewLexer(tt.input)
			tokens := lexer.Tokenize()
			kinds := make([]TokenKind, len(tokens))
			for i, tok := range tokens {
				kinds[i] = tok.Kind
			}
			assert.Equal(t, tt.tokens, kinds)
		})
	}
}

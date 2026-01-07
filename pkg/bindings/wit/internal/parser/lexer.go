package parser

import (
	"strings"
	"unicode"
	"unicode/utf8"
)

// Lexer tokenizes WIT source code.
type Lexer struct {
	input  string
	pos    int  // current position in input (points to current char)
	line   int  // current line number (1-indexed)
	column int  // current column number (1-indexed)
	start  int  // start position of current token
	startLine   int
	startColumn int
}

// NewLexer creates a new Lexer for the given input.
func NewLexer(input string) *Lexer {
	return &Lexer{
		input:  input,
		pos:    0,
		line:   1,
		column: 1,
	}
}

// NextToken returns the next token from the input.
func (l *Lexer) NextToken() Token {
	l.skipWhitespaceAndComments()

	l.start = l.pos
	l.startLine = l.line
	l.startColumn = l.column

	if l.pos >= len(l.input) {
		return l.makeToken(TokenEOF, "")
	}

	ch := l.peek()

	// Single-character tokens
	switch ch {
	case '(':
		l.advance()
		return l.makeToken(TokenLParen, "(")
	case ')':
		l.advance()
		return l.makeToken(TokenRParen, ")")
	case '{':
		l.advance()
		return l.makeToken(TokenLBrace, "{")
	case '}':
		l.advance()
		return l.makeToken(TokenRBrace, "}")
	case '<':
		l.advance()
		return l.makeToken(TokenLAngle, "<")
	case '>':
		l.advance()
		return l.makeToken(TokenRAngle, ">")
	case ',':
		l.advance()
		return l.makeToken(TokenComma, ",")
	case ':':
		l.advance()
		return l.makeToken(TokenColon, ":")
	case ';':
		l.advance()
		return l.makeToken(TokenSemicolon, ";")
	case '=':
		l.advance()
		return l.makeToken(TokenEqual, "=")
	case '*':
		l.advance()
		return l.makeToken(TokenStar, "*")
	case '.':
		l.advance()
		return l.makeToken(TokenDot, ".")
	case '@':
		l.advance()
		return l.makeToken(TokenAt, "@")
	case '%':
		l.advance()
		return l.makeToken(TokenPercent, "%")
	case '_':
		// Check if this is a standalone underscore or part of an identifier
		if !l.isIdentChar(l.peekNext()) {
			l.advance()
			return l.makeToken(TokenUnderscore, "_")
		}
	case '-':
		// Check for arrow ->
		l.advance()
		if l.peek() == '>' {
			l.advance()
			return l.makeToken(TokenArrow, "->")
		}
		// A lone '-' is an error in WIT
		return l.makeToken(TokenError, "unexpected '-'")
	case '/':
		l.advance()
		return l.makeToken(TokenSlash, "/")
	}

	// Integer literals
	if isDigit(ch) {
		return l.scanInteger()
	}

	// Identifiers and keywords
	if l.isIdentStart(ch) {
		return l.scanIdentifier()
	}

	// Unknown character
	l.advance()
	return l.makeToken(TokenError, string(ch))
}

// Peek returns all tokens without consuming them (for debugging).
func (l *Lexer) Tokenize() []Token {
	tokens := []Token{}
	for {
		tok := l.NextToken()
		tokens = append(tokens, tok)
		if tok.Kind == TokenEOF || tok.Kind == TokenError {
			break
		}
	}
	return tokens
}

// skipWhitespaceAndComments skips whitespace and comments, capturing doc comments.
func (l *Lexer) skipWhitespaceAndComments() {
	for l.pos < len(l.input) {
		ch := l.peek()

		if ch == ' ' || ch == '\t' || ch == '\r' {
			l.advance()
			continue
		}

		if ch == '\n' {
			l.advance()
			continue
		}

		// Check for comments
		if ch == '/' && l.pos+1 < len(l.input) {
			next := l.input[l.pos+1]
			if next == '/' {
				// Line comment - check for doc comment
				l.skipLineComment()
				continue
			}
			if next == '*' {
				// Block comment
				l.skipBlockComment()
				continue
			}
		}

		break
	}
}

// skipLineComment skips a line comment (// ...).
func (l *Lexer) skipLineComment() {
	l.advance() // skip first /
	l.advance() // skip second /

	for l.pos < len(l.input) && l.peek() != '\n' {
		l.advance()
	}
}

// skipBlockComment skips a block comment (/* ... */), handling nesting.
func (l *Lexer) skipBlockComment() {
	l.advance() // skip /
	l.advance() // skip *
	depth := 1

	for l.pos < len(l.input) && depth > 0 {
		ch := l.peek()

		if ch == '/' && l.pos+1 < len(l.input) && l.input[l.pos+1] == '*' {
			l.advance()
			l.advance()
			depth++
			continue
		}

		if ch == '*' && l.pos+1 < len(l.input) && l.input[l.pos+1] == '/' {
			l.advance()
			l.advance()
			depth--
			continue
		}

		l.advance()
	}
}

// scanInteger scans an integer literal.
func (l *Lexer) scanInteger() Token {
	for l.pos < len(l.input) && isDigit(l.peek()) {
		l.advance()
	}
	return l.makeToken(TokenInteger, l.input[l.start:l.pos])
}

// scanIdentifier scans an identifier or keyword.
// WIT identifiers are kebab-case: [a-z][a-z0-9]*(-[a-z][a-z0-9]*)*
func (l *Lexer) scanIdentifier() Token {
	// Already validated first char is valid start
	l.advance()

	for l.pos < len(l.input) {
		ch := l.peek()
		if l.isIdentChar(ch) {
			l.advance()
		} else {
			break
		}
	}

	value := l.input[l.start:l.pos]

	// Check if this is a keyword
	kind := LookupKeyword(value)
	return l.makeToken(kind, value)
}

// isIdentStart returns true if ch can start an identifier.
func (l *Lexer) isIdentStart(ch byte) bool {
	return (ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z') || ch == '_'
}

// isIdentChar returns true if ch can continue an identifier.
func (l *Lexer) isIdentChar(ch byte) bool {
	return (ch >= 'a' && ch <= 'z') ||
		(ch >= 'A' && ch <= 'Z') ||
		(ch >= '0' && ch <= '9') ||
		ch == '-' || ch == '_'
}

// peek returns the current character without advancing.
func (l *Lexer) peek() byte {
	if l.pos >= len(l.input) {
		return 0
	}
	return l.input[l.pos]
}

// peekNext returns the next character without advancing.
func (l *Lexer) peekNext() byte {
	if l.pos+1 >= len(l.input) {
		return 0
	}
	return l.input[l.pos+1]
}

// advance moves to the next character.
func (l *Lexer) advance() byte {
	if l.pos >= len(l.input) {
		return 0
	}
	ch := l.input[l.pos]
	l.pos++
	if ch == '\n' {
		l.line++
		l.column = 1
	} else {
		l.column++
	}
	return ch
}

// makeToken creates a token with the current position info.
func (l *Lexer) makeToken(kind TokenKind, value string) Token {
	return Token{
		Kind:  kind,
		Value: value,
		Pos: Position{
			Offset: l.start,
			Line:   l.startLine,
			Column: l.startColumn,
		},
		EndPos: Position{
			Offset: l.pos,
			Line:   l.line,
			Column: l.column,
		},
	}
}

// isDigit returns true if ch is a digit.
func isDigit(ch byte) bool {
	return ch >= '0' && ch <= '9'
}

// Helper functions that might be needed for Unicode support in the future.
var _ = unicode.IsLetter
var _ = utf8.DecodeRuneInString
var _ = strings.Builder{}

package parser

import "fmt"

// TokenKind represents the type of a lexical token.
type TokenKind int

const (
	// Special tokens
	TokenEOF TokenKind = iota
	TokenError
	TokenComment
	TokenDocComment

	// Literals
	TokenIdent   // identifier (kebab-case)
	TokenInteger // integer literal

	// Punctuation
	TokenLParen    // (
	TokenRParen    // )
	TokenLBrace    // {
	TokenRBrace    // }
	TokenLAngle    // <
	TokenRAngle    // >
	TokenComma     // ,
	TokenColon     // :
	TokenSemicolon // ;
	TokenEqual     // =
	TokenArrow     // ->
	TokenStar      // *
	TokenSlash     // /
	TokenDot       // .
	TokenAt        // @
	TokenPercent   // %
	TokenUnderscore // _

	// Keywords
	TokenPackage
	TokenInterface
	TokenWorld
	TokenFunc
	TokenType
	TokenRecord
	TokenVariant
	TokenEnum
	TokenFlags
	TokenResource
	TokenUse
	TokenAs
	TokenImport
	TokenExport
	TokenInclude
	TokenWith
	TokenConstructor
	TokenStatic
	TokenAsync
	TokenOwn
	TokenBorrow

	// Built-in types
	TokenU8
	TokenU16
	TokenU32
	TokenU64
	TokenS8
	TokenS16
	TokenS32
	TokenS64
	TokenF32
	TokenF64
	TokenBool
	TokenChar
	TokenString
	TokenList
	TokenOption
	TokenResult
	TokenTuple
	TokenFuture
	TokenStream
)

// Token represents a lexical token in WIT.
type Token struct {
	Kind   TokenKind
	Value  string
	Pos    Position
	EndPos Position
}

// Position represents a location in source code.
type Position struct {
	Offset int // byte offset
	Line   int // 1-indexed line number
	Column int // 1-indexed column number (in bytes)
}

func (p Position) String() string {
	return fmt.Sprintf("%d:%d", p.Line, p.Column)
}

// String returns a human-readable representation of the token.
func (t Token) String() string {
	if t.Value != "" {
		return fmt.Sprintf("%s(%q) at %s", t.Kind, t.Value, t.Pos)
	}
	return fmt.Sprintf("%s at %s", t.Kind, t.Pos)
}

// String returns the name of the token kind.
func (k TokenKind) String() string {
	switch k {
	case TokenEOF:
		return "EOF"
	case TokenError:
		return "Error"
	case TokenComment:
		return "Comment"
	case TokenDocComment:
		return "DocComment"
	case TokenIdent:
		return "Ident"
	case TokenInteger:
		return "Integer"
	case TokenLParen:
		return "LParen"
	case TokenRParen:
		return "RParen"
	case TokenLBrace:
		return "LBrace"
	case TokenRBrace:
		return "RBrace"
	case TokenLAngle:
		return "LAngle"
	case TokenRAngle:
		return "RAngle"
	case TokenComma:
		return "Comma"
	case TokenColon:
		return "Colon"
	case TokenSemicolon:
		return "Semicolon"
	case TokenEqual:
		return "Equal"
	case TokenArrow:
		return "Arrow"
	case TokenStar:
		return "Star"
	case TokenSlash:
		return "Slash"
	case TokenDot:
		return "Dot"
	case TokenAt:
		return "At"
	case TokenPercent:
		return "Percent"
	case TokenUnderscore:
		return "Underscore"
	case TokenPackage:
		return "package"
	case TokenInterface:
		return "interface"
	case TokenWorld:
		return "world"
	case TokenFunc:
		return "func"
	case TokenType:
		return "type"
	case TokenRecord:
		return "record"
	case TokenVariant:
		return "variant"
	case TokenEnum:
		return "enum"
	case TokenFlags:
		return "flags"
	case TokenResource:
		return "resource"
	case TokenUse:
		return "use"
	case TokenAs:
		return "as"
	case TokenImport:
		return "import"
	case TokenExport:
		return "export"
	case TokenInclude:
		return "include"
	case TokenWith:
		return "with"
	case TokenConstructor:
		return "constructor"
	case TokenStatic:
		return "static"
	case TokenAsync:
		return "async"
	case TokenOwn:
		return "own"
	case TokenBorrow:
		return "borrow"
	case TokenU8:
		return "u8"
	case TokenU16:
		return "u16"
	case TokenU32:
		return "u32"
	case TokenU64:
		return "u64"
	case TokenS8:
		return "s8"
	case TokenS16:
		return "s16"
	case TokenS32:
		return "s32"
	case TokenS64:
		return "s64"
	case TokenF32:
		return "f32"
	case TokenF64:
		return "f64"
	case TokenBool:
		return "bool"
	case TokenChar:
		return "char"
	case TokenString:
		return "string"
	case TokenList:
		return "list"
	case TokenOption:
		return "option"
	case TokenResult:
		return "result"
	case TokenTuple:
		return "tuple"
	case TokenFuture:
		return "future"
	case TokenStream:
		return "stream"
	default:
		return fmt.Sprintf("Unknown(%d)", k)
	}
}

// keywords maps keyword strings to their token kinds.
var keywords = map[string]TokenKind{
	"package":     TokenPackage,
	"interface":   TokenInterface,
	"world":       TokenWorld,
	"func":        TokenFunc,
	"type":        TokenType,
	"record":      TokenRecord,
	"variant":     TokenVariant,
	"enum":        TokenEnum,
	"flags":       TokenFlags,
	"resource":    TokenResource,
	"use":         TokenUse,
	"as":          TokenAs,
	"import":      TokenImport,
	"export":      TokenExport,
	"include":     TokenInclude,
	"with":        TokenWith,
	"constructor": TokenConstructor,
	"static":      TokenStatic,
	"async":       TokenAsync,
	"own":         TokenOwn,
	"borrow":      TokenBorrow,
	// Built-in types
	"u8":     TokenU8,
	"u16":    TokenU16,
	"u32":    TokenU32,
	"u64":    TokenU64,
	"s8":     TokenS8,
	"s16":    TokenS16,
	"s32":    TokenS32,
	"s64":    TokenS64,
	"f32":    TokenF32,
	"f64":    TokenF64,
	"bool":   TokenBool,
	"char":   TokenChar,
	"string": TokenString,
	"list":   TokenList,
	"option": TokenOption,
	"result": TokenResult,
	"tuple":  TokenTuple,
	"future": TokenFuture,
	"stream": TokenStream,
}

// LookupKeyword returns the token kind for a keyword, or TokenIdent if not a keyword.
func LookupKeyword(ident string) TokenKind {
	if kind, ok := keywords[ident]; ok {
		return kind
	}
	return TokenIdent
}

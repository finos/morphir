package xcontext

import (
	"context"
	"github.com/finos/morphir/devkit/go/morphircli/session"
)

type Context struct {
	underlying context.Context
}

func (ctx *Context) Session() *session.Session {
	s := ctx.underlying.Value(SessionKey)
	if s == nil {
		return nil
	}

	switch sessionResolved := s.(type) {
	case *session.Session:
		return sessionResolved
	default:
		return nil
	}
}

func New(ctx context.Context) *Context {
	return &Context{underlying: ctx}
}

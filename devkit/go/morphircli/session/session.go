package session

import (
	"context"
	"errors"
	"github.com/finos/morphir/devkit/go/internal/backend/inprocess"
	"github.com/finos/morphir/devkit/go/morphircli"
	"github.com/hack-pad/hackpadfs"
	"github.com/hack-pad/hackpadfs/os"
	"github.com/phuslu/log"
)

type Session struct {
	inProcess        bool
	fs               *hackpadfs.FS
	inprocessSession *inprocess.Session
}

type Option func(*Session)

func New(opts ...Option) *Session {
	const (
		defaultInProcess = false
	)

	session := &Session{
		inProcess: defaultInProcess,
	}

	for _, option := range opts {
		option(session)
	}
	return initSession(session)
}

func (s *Session) connect(connection morphircli.Connection) error {
	return nil
}

func (s *Session) discoverServer() (*morphircli.Connection, error) {
	return nil, errors.New("not implemented")
}

func (s *Session) connectDynamically() (*morphircli.ConnectionInfo, error) {
	return nil, errors.New("not implemented")
}

// UsingInProcessServer is a session option that configures the session to run in-process.
func UsingInProcessServer() Option {
	return func(session *Session) {
		session.inProcess = true
	}
}

// UsingOutOfProcessServer is a session option that configures the session to run as an inter-process communication client.
func UsingOutOfProcessServer() Option {
	return func(session *Session) {
		session.inProcess = false
	}
}

func UsingFs(fs *hackpadfs.FS) Option {
	return func(session *Session) {
		session.fs = fs
	}
}

func (s *Session) Start(ctx context.Context) error {
	if s.inProcess {
		return s.startInProcess(ctx)
	}
	return s.startIpc(ctx)
}

func (s *Session) startInProcess(ctx context.Context) error {
	log.Info().Msg("Starting in-process session")
	s.inprocessSession = inprocess.New()
	return nil
}

func (s *Session) startIpc(ctx context.Context) error {
	// TODO: Connect and possibly start op the out-of-process server
	log.Info().Msg("Starting IPC session")
	return nil
}

func (s *Session) Stop() error {
	log.Info().Msg("Stopping session...")
	log.Info().Msg("Session stopped")
	return nil
}

func (s *Session) Close() error {
	log.Info().Msg("Closing session...")
	if s.inprocessSession != nil {
		s.inprocessSession.Close()
		s.inprocessSession = nil
	}
	err := s.Stop()
	log.Info().Msg("Session closed")
	return err
}

func initSession(session *Session) *Session {
	if session.fs == nil {
		fs := hackpadfs.FS(os.NewFS())
		session.fs = &fs
	}
	return session
}

package session

import (
	"context"
	"errors"
	"github.com/anthdm/hollywood/actor"
	"github.com/finos/morphir/devkit/go/internal/broker"
	"github.com/finos/morphir/devkit/go/morphircli"
	"github.com/finos/morphir/devkit/go/morphircli/task"
	"github.com/hack-pad/hackpadfs"
	"github.com/hack-pad/hackpadfs/os"
	"github.com/phuslu/log"
	"time"
)

type Session struct {
	inProcess bool
	fs        *hackpadfs.FS
	brokerPID *actor.PID
	engine    *actor.Engine
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

func (s *Session) GetMessageBroker() MessageBroker {
	return s
}

func (s *Session) SubmitTask(task task.Task) error {
	return s.Send(task)
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

func (s *Session) Send(msg any) error {
	if s.brokerPID == nil {
		return errors.New("broker not initialized")
	}
	s.engine.Send(s.brokerPID, msg)
	return nil
}

func (s *Session) Request(msg any, timeout time.Duration) any {
	response := s.engine.Request(s.brokerPID, msg, timeout)
	return response
}

func (s *Session) Start(ctx context.Context) error {
	log.Info().Msg("Starting session...")
	var brokerPID *actor.PID
	if s.inProcess {
		brokerPID = s.engine.Spawn(broker.NewBroker(true), "broker")
	} else {
		brokerPID = s.engine.Spawn(broker.NewBroker(false), "broker")
	}
	s.brokerPID = brokerPID
	log.Info().Msg("Session started")
	return nil
}

func (s *Session) Stop() error {
	log.Info().Msg("Stopping session...")
	log.Info().Msg("Session stopped")
	return nil
}

func (s *Session) Close() error {
	log.Info().Msg("Closing session...")
	err := s.Stop()
	log.Info().Msg("Session closed")
	return err
}

func initSession(session *Session) *Session {
	if session.fs == nil {
		fs := hackpadfs.FS(os.NewFS())
		session.fs = &fs
	}
	if session.engine == nil {
		eng, err := actor.NewEngine(actor.NewEngineConfig())
		if err != nil {
			log.Error().Err(err).Msg("error initializing underlying actor engine")
		}
		session.engine = eng
	}
	return session
}

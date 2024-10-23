package session

import (
	"context"
	"errors"
	"fmt"
	"github.com/finos/morphir/devkit/go/messaging/broker"
	"time"

	"github.com/anthdm/hollywood/actor"
	"github.com/finos/morphir/devkit/go/config/configmgr"
	"github.com/finos/morphir/devkit/go/tasks/task"

	brokerSvc "github.com/finos/morphir/devkit/go/internal/broker"
	configmgrSvc "github.com/finos/morphir/devkit/go/internal/configmgr"

	"github.com/hack-pad/hackpadfs"
	"github.com/hack-pad/hackpadfs/os"
	"github.com/phuslu/log"
)

var CurrentSession *Session

type Session struct {
	inProcess     bool
	fs            *hackpadfs.FS
	configMgr     *configmgrSvc.Service
	brokerService *broker.Broker
	engine        *actor.Engine
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

func (s *Session) GetConfigMgr() configmgr.ConfigMgr {
	return s.configMgr
}

func PostToConfigMgr[Msg configmgr.ValidMessages](session *Session, msg Msg) {
	if session == nil {
		log.Error().Msg("The provided session is nil")
		return
	}
	svc := session.configMgr
	if svc == nil {
		log.Error().Msg("ConfigMgr service not initialized")
		return
	}
	configmgrSvc.ApplyMsg(*svc, msg)
}

func (s *Session) SubmitTask(task task.Task) error {
	return s.Send(task)
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
	var brokerService *broker.Broker = s.brokerService
	if brokerService == nil {
		return errors.New("broker not initialized")
	}
	return (*brokerService).Send(msg)
}

func (s *Session) Request(msg any, timeout time.Duration) (response any, err error) {
	var brokerService *broker.Broker = s.brokerService
	if brokerService == nil {
		return nil, errors.New("broker not initialized")
	}
	return (*brokerService).Request(msg, timeout)
}

func (s *Session) Start(ctx context.Context) error {
	log.Info().Msg("Starting session...")
	//var brokerPID *actor.PID
	//if s.inProcess {
	//	brokerPID = s.engine.Spawn(broker.NewBroker(true), "broker")
	//} else {
	//	brokerPID = s.engine.Spawn(broker.NewBroker(false), "broker")
	//}
	//s.brokerPID = brokerPID
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
		eng, err := initActorSystem(session)
		if err != nil {
			log.Error().Err(err).Msg("error initializing underlying actor engine")
		}
		session.engine = eng
	}

	CurrentSession = session
	return session
}

func initActorSystem(session *Session) (*actor.Engine, error) {
	engine, err := actor.NewEngine(actor.NewEngineConfig())
	if err != nil {
		err = fmt.Errorf("error initializing underlying actor engine: %w", err)
		return nil, err
	}

	// Create ConfigMgr
	session.configMgr = createConfigMgr(engine)

	// Create Broker Service
	session.brokerService = createBroker(engine, session.inProcess)

	return engine, nil
}

func createConfigMgr(engine *actor.Engine) *configmgrSvc.Service {
	cfg := configmgrSvc.Config{}
	mgr := configmgrSvc.NewService(engine, cfg)
	return mgr
}

func createBroker(engine *actor.Engine, inProcess bool) *broker.Broker {
	cfg := brokerSvc.Config{
		InProcess: inProcess,
	}
	svc := brokerSvc.New(engine, cfg)
	return &svc
}

package messaging

import "time"

type Sender interface {
	Send(msg any) error
}

type FireAndForgetSender interface {
	Send(msg any)
}

type Requester interface {
	Request(request any, timeout time.Duration) (response any, err error)
}

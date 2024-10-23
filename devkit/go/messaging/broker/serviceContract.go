package broker

import "time"

type Broker interface {
	// InProcess indicates whether this is an in-process broker.
	// This will return `true` for in-process brokers and `false` otherwise
	InProcess() bool

	// Publish publishes a message to the provided topic. Publish is fire and forget and will not fail if there
	// are not any listeners.
	Publish(topic string, msg any) error

	// Send sends a message. The message is expected to have a handler that the broker is capable of resolving and
	// will fail if the broker cannot determine the message's target.
	Send(msg any) error

	// Request makes a request to the broker with the expectation of some response.
	Request(request any, timeout time.Duration) (response any, err error)
}

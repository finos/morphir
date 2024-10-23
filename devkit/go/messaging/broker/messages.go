package broker

import "fmt"

type PublishMessage struct {
	Topic   string
	Message any
}

type SendMessage struct {
	Message any
}

type NoHandlerFoundForMessageError[Msg any] struct {
	Message Msg
}

func (e NoHandlerFoundForMessageError[Msg]) Error() string {
	return fmt.Sprintf("No handler found for message: %+v", e.Message)
}

type MakeRequest struct {
	Request any
}

type RequestError struct {
	Request any
	Message string
}

type ResponseError struct {
	RequestError
	Response *any
}

func (e RequestError) Error() string {
	return fmt.Sprintf("Error making request: %s", e.Message)
}

func (e ResponseError) Error() string {
	return fmt.Sprintf("Error encountered while responding to request: %s", e.Message)
}

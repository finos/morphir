package morphircli

import "errors"

type Client struct{}

func NewClient(options ...func(client *Client)) *Client {
	client := &Client{}
	for _, option := range options {
		option(client)
	}
	return client
}

func (c *Client) Connect(connection Connection) error {
	return nil
}

func (c *Client) DiscoverServer() (*Connection, error) {
	return nil, errors.New("not implemented")
}

func (c *Client) ConnectDynamically() (*ConnectionInfo, error) {
	return nil, errors.New("not implemented")
}

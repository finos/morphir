package morphircli

type ConnectionInfo interface {
	IP() string
	Port() int
}

type Connection struct {
	ip   string
	port int
}

func (c *Connection) IP() string {
	return c.ip
}

func (c *Connection) Port() int {
	return c.port
}

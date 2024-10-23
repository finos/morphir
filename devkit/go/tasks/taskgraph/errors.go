package taskgraph

type NodeAlreadyExistsError struct {
	Node NodeId
}

func (e NodeAlreadyExistsError) Error() string {
	return "Node already exists: " + string(e.Node)
}

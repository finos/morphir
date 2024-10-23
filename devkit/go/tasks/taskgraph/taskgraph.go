package taskgraph

import (
	"fmt"
	"iter"
	"maps"
)

type TaskGraph interface {
	AllEdges() iter.Seq[Edge]
	AllNodes() iter.Seq[NodeId]
	Add(node NodeId) error
	Connect(start, end NodeId) error
	Exists(node NodeId) bool
	Traverse() iter.Seq[NodeId]
}

func String(g TaskGraph) string {
	var result string
	for node := range g.AllNodes() {
		result += string(node) + " -> "
		for edge := range g.AllEdges() {
			if edge.GetStart() == node {
				result += string(edge.GetEnd()) + ", "
			}
		}
		result += "\n"
	}
	return result
}

type taskGraph struct {
	edges []Edge
	nodes map[NodeId]any
}

func New() TaskGraph {
	return &taskGraph{
		nodes: make(map[NodeId]any),
	}
}

func AnyEdges[T TaskGraph](g T, f func(Edge) bool) bool {
	for edge := range g.AllEdges() {
		if f(edge) {
			return true
		}
	}
	return false
}

func (g *taskGraph) Exists(node NodeId) bool {
	_, ok := g.nodes[node]
	return ok
}

func (g *taskGraph) AllEdges() iter.Seq[Edge] {
	return func(yield func(Edge) bool) {
		for _, edge := range g.edges {
			if !yield(edge) {
				return
			}
		}
	}
}

func (g *taskGraph) AllNodes() iter.Seq[NodeId] {
	return maps.Keys(g.nodes)
}

func (g *taskGraph) Add(node NodeId) error {
	if g.Exists(node) {
		return NodeAlreadyExistsError{Node: node}
	}
	g.nodes[node] = nil
	return nil
}

func (g *taskGraph) Connect(start, end NodeId) error {

	if start == end {
		return fmt.Errorf("reflexive edges are not allowed in the graph: %s -> %s", start, end)
	}

	if AnyEdges(g, func(edge Edge) bool {
		return edge.GetStart() == end && edge.GetEnd() == start
	}) {
		return fmt.Errorf("cycles are not allowed in the graph: %s -> %s", start, end)
	}

	if AnyEdges(g, func(edge Edge) bool {
		return edge.GetStart() == start && edge.GetEnd() == end
	}) {
		// edge already exists
		return nil
	}

	if !g.Exists(start) == false {
		_ = g.Add(start)
	}
	if !g.Exists(end) == false {
		_ = g.Add(end)
	}
	g.edges = append(g.edges, NewEdge(start, end))
	return nil
}

func (g *taskGraph) Traverse() iter.Seq[NodeId] {
	return func(yield func(NodeId) bool) {
		visited := make(map[NodeId]bool)
		for node := range g.AllNodes() {
			g.traverse(node, visited)(yield)
		}
	}
}

func (g *taskGraph) traverse(node NodeId, visited map[NodeId]bool) iter.Seq[NodeId] {
	return func(yield func(NodeId) bool) {
		if visited[node] {
			return
		}
		visited[node] = true
		if !yield(node) {
			return
		}
		for edge := range g.AllEdges() {
			if edge.GetStart() == node {
				g.traverse(edge.GetEnd(), visited)(yield)
			}
		}
	}
}

type Edge interface {
	GetStart() NodeId
	GetEnd() NodeId
}

type edge struct {
	Start NodeId
	End   NodeId
}

func NewEdge(start, end NodeId) Edge {
	return edge{Start: start, End: end}
}

func (e edge) GetStart() NodeId {
	return e.Start
}

func (e edge) GetEnd() NodeId {
	return e.End
}

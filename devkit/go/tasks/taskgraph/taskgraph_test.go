package taskgraph

import (
	"github.com/stretchr/testify/assert"
	"testing"
)

func TestTaskGraph_ShouldNotAllowReflexiveEdges(t *testing.T) {
	sut := New()
	nodeA := NodeId("a")
	err := sut.Connect(nodeA, nodeA)
	if err == nil {
		t.Error("Expected error when connecting node to itself")
	}
}

func TestTaskGraph_NodeTraversal_ShouldBeComplete(t *testing.T) {
	sut := New()
	nodeA := NodeId("a")
	nodeB := NodeId("b")
	nodeC := NodeId("c")
	sut.Add(nodeA)
	sut.Add(nodeB)
	sut.Add(nodeC)
	sut.Connect(nodeA, nodeB)
	sut.Connect(nodeB, nodeC)
	sut.Connect(nodeC, nodeA)
	var traversed []NodeId
	for node := range sut.Traverse() {
		traversed = append(traversed, node)
	}
	if len(traversed) != 3 {
		t.Error("Expected 3 nodes to be traversed")
	}
	assert.Equal(t, []NodeId{nodeA, nodeB, nodeC}, traversed)
}

func TestTaskGraph_ShouldNotAllowCycles(t *testing.T) {
	sut := New()
	nodeA := NodeId("a")
	nodeB := NodeId("b")
	nodeC := NodeId("c")
	sut.Add(nodeA)
	sut.Add(nodeB)
	sut.Add(nodeC)
	sut.Connect(nodeA, nodeB)
	sut.Connect(nodeB, nodeC)
	err := sut.Connect(nodeC, nodeA)
	if err == nil {
		graph := String(sut)
		t.Error("Expected error when connecting node to itself, given:", graph)
	}
}

func TestTaskGraph_AnyEdgers_ShouldReturnTrueForMatchingEdges(t *testing.T) {
	sut := New()
	nodeA := NodeId("a")
	nodeB := NodeId("b")
	sut.Add(nodeA)
	sut.Add(nodeB)
	sut.Connect(nodeA, nodeB)
	result := AnyEdges(sut, func(edge Edge) bool {
		return edge.GetStart() == nodeA && edge.GetEnd() == nodeB
	})
	assert.True(t, result)
}

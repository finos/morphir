///|
/// One step of a let chain: one declaration, or a group of declarations that
/// refer to each other (or one that refers to itself). The ids are declaration
/// indexes in source order.
pub(all) enum LetGroup {
  Single(Int)
  Recursive(Array[Int])
} derive(Eq, Debug)

///|
pub extend LetGroup with Eq::{equal, not_equal}

///|
pub extend LetGroup with @debug.Debug::{to_repr}

///|
/// The let chain of a let block, outermost first, as morphir-elm's
/// `mapLetExpression` builds it with elm-community/graph 6.0.0. `edges[i]` lists
/// the declarations that declaration `i` mentions.
///
/// Without a cycle (`stronglyConnectedComponents` is `Ok`), the chain is the
/// DFS post-order: `topologicalSort` gives the reverse post-order and the
/// `foldl` wraps its first element innermost. With a cycle, the chain is the
/// reverse of the Kosaraju components (`dfsForest reversePostOrder (reverseEdges
/// graph)`), because the `foldl` wraps the first component innermost. A
/// component of one declaration without a self edge is `Single`; any other is
/// `Recursive`.
pub fn let_groups(edges : Array[Array[Int]]) -> Array[LetGroup] {
  let n = edges.length()
  let outgoing = adjacency(n, edges)
  // The reversed graph. `from` grows, so each list is ascending, as
  // `IntDict.keys` of the incoming edges is.
  let incoming : Array[Array[Int]] = Array::makei(n, _ => [])
  for from in 0..<n {
    for to in outgoing[from] {
      incoming[to].push(from)
    }
  }
  let post_order : Array[Int] = []
  for tree in dfs_forest(outgoing, Array::makei(n, i => i)) {
    post_order.append(tree)
  }
  let reverse_post_order = post_order.copy()
  reverse_post_order.rev_in_place()
  let components = dfs_forest(incoming, reverse_post_order)
  let self_edge = (i : Int) => outgoing[i].contains(i)
  let cyclic = components.iter().any(c => c.length() > 1 || self_edge(c[0]))
  if !cyclic {
    return post_order.map(i => Single(i))
  }
  let groups : Array[LetGroup] = []
  for k = components.length() - 1; k >= 0; k = k - 1 {
    let component = components[k]
    if component is [i] && !self_edge(i) {
      groups.push(Single(i))
    } else {
      let ids = component.copy()
      ids.sort()
      groups.push(Recursive(ids))
    }
  }
  groups
}

///|
/// The outgoing edges of each node: unique, in range and ascending.
fn adjacency(n : Int, edges : Array[Array[Int]]) -> Array[Array[Int]] {
  Array::makei(n, i => {
    let targets : Array[Int] = []
    for to in edges[i] {
      if to >= 0 && to < n && !targets.contains(to) {
        targets.push(to)
      }
    }
    targets.sort()
    targets
  })
}

///|
/// A depth-first forest, as elm-community/graph's `guidedDfs`: a tree is grown
/// from each seed that is not visited yet, in seed order, and each node visits
/// its neighbors in the order of `neighbors`. Each tree lists its nodes in
/// post-order (a node after all of its descendants).
fn dfs_forest(
  neighbors : Array[Array[Int]],
  seeds : Array[Int],
) -> Array[Array[Int]] {
  let visited = Array::make(neighbors.length(), false)
  let forest : Array[Array[Int]] = []
  for seed in seeds {
    if visited[seed] {
      continue
    }
    let tree : Array[Int] = []
    // An explicit stack of (node, index of the next neighbor) keeps deep let
    // chains off the call stack.
    let stack : Array[(Int, Int)] = [(seed, 0)]
    visited[seed] = true
    while stack.last() is Some((node, next)) {
      if next < neighbors[node].length() {
        stack[stack.length() - 1] = (node, next + 1)
        let to = neighbors[node][next]
        if !visited[to] {
          visited[to] = true
          stack.push((to, 0))
        }
      } else {
        ignore(stack.pop())
        tree.push(node)
      }
    }
    forest.push(tree)
  }
  forest
}

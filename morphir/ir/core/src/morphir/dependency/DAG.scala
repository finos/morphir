package morphir.dependency

/** Generated based on Dependency.DAG
*/
object DAG{

  implicit def comparableOrdering[ComparableNode]: Ordering[ComparableNode] =(_: ComparableNode, _: ComparableNode) => 0

  final case class CycleDetected[ComparableNode](
    arg1: ComparableNode,
    arg2: ComparableNode
  ){}
  
  final case class DAG[ComparableNode](
    arg1: morphir.sdk.Dict.Dict[ComparableNode, morphir.sdk.Set.Set[ComparableNode]]
  ) extends scala.AnyVal{}
  
  def backwardTopologicalOrdering[ComparableNode]: morphir.dependency.DAG.DAG[ComparableNode] => morphir.sdk.List.List[morphir.sdk.List.List[ComparableNode]] =
    ({
      case morphir.dependency.DAG.DAG(dag) => 
        {
          def removeStartNodes: ((morphir.dependency.DAG.DAG[ComparableNode], morphir.sdk.List.List[morphir.sdk.List.List[ComparableNode]])) => (morphir.dependency.DAG.DAG[ComparableNode], morphir.sdk.List.List[morphir.sdk.List.List[ComparableNode]]) =
            ({
              case (morphir.dependency.DAG.DAG(d), topologicalOrder) => 
                {
                  val dagWithoutStartNodes: morphir.dependency.DAG.DAG[ComparableNode] = (morphir.dependency.DAG.DAG(morphir.sdk.Dict.filter(((node: ComparableNode) =>
                    ({
                      case _ => 
                        morphir.sdk.Basics.not(morphir.sdk.Set.isEmpty(morphir.dependency.DAG.incomingEdges(node)((morphir.dependency.DAG.DAG(d) : morphir.dependency.DAG.DAG[ComparableNode]))))
                    } : morphir.sdk.Set.Set[ComparableNode] => morphir.sdk.Basics.Bool)))(d)) : morphir.dependency.DAG.DAG[ComparableNode])
                  
                  val collectStartNodes: morphir.sdk.List.List[ComparableNode] = morphir.sdk.List.filterMap(({
                    case (comparableNode, _) => 
                      if (morphir.sdk.Set.isEmpty(morphir.dependency.DAG.incomingEdges(comparableNode)((morphir.dependency.DAG.DAG(d) : morphir.dependency.DAG.DAG[ComparableNode])))) {
                        (morphir.sdk.Maybe.Just(comparableNode) : morphir.sdk.Maybe.Maybe[ComparableNode])
                      } else {
                        (morphir.sdk.Maybe.Nothing : morphir.sdk.Maybe.Maybe[ComparableNode])
                      }
                  } : ((ComparableNode, morphir.sdk.Set.Set[ComparableNode])) => morphir.sdk.Maybe.Maybe[ComparableNode]))(morphir.sdk.Dict.toList(d))
                  
                  if (morphir.sdk.Dict.isEmpty(d)) {
                    ((morphir.dependency.DAG.DAG(morphir.sdk.Dict.empty) : morphir.dependency.DAG.DAG[ComparableNode]), topologicalOrder)
                  } else {
                    removeStartNodes((dagWithoutStartNodes, morphir.sdk.List.cons(collectStartNodes)(topologicalOrder)))
                  }
                }
            } : ((morphir.dependency.DAG.DAG[ComparableNode], morphir.sdk.List.List[morphir.sdk.List.List[ComparableNode]])) => (morphir.dependency.DAG.DAG[ComparableNode], morphir.sdk.List.List[morphir.sdk.List.List[ComparableNode]]))
          
          morphir.sdk.Tuple.second(removeStartNodes(((morphir.dependency.DAG.DAG(morphir.sdk.Dict.map(morphir.sdk.Set.remove[ComparableNode])(dag)) : morphir.dependency.DAG.DAG[ComparableNode]), morphir.sdk.List(
          
          ))))
        }
    } : morphir.dependency.DAG.DAG[ComparableNode] => morphir.sdk.List.List[morphir.sdk.List.List[ComparableNode]])
  
  def collectForwardReachableNodes[ComparableNode](
    firstNode: ComparableNode
  ): morphir.dependency.DAG.DAG[ComparableNode] => morphir.sdk.Set.Set[ComparableNode] =
    ({
      case morphir.dependency.DAG.DAG(initialEdgesByNode) => 
        {
          val firstReachableNodes: morphir.sdk.Set.Set[ComparableNode] = morphir.sdk.Maybe.withDefault(morphir.sdk.Set.empty[ComparableNode])(morphir.sdk.Dict.get(firstNode)(initialEdgesByNode))
          
          {
            def collect(
              reachableSoFar: morphir.sdk.Set.Set[ComparableNode]
            )(
              currentEdgesByNode: morphir.sdk.Dict.Dict[ComparableNode, morphir.sdk.Set.Set[ComparableNode]]
            ): morphir.sdk.Set.Set[ComparableNode] = {
              val (reachableEdges, unreachableEdges) = morphir.sdk.Dict.partition(((fromNode: ComparableNode) =>
                ({
                  case _ => 
                    morphir.sdk.Set.member(fromNode)(reachableSoFar)
                } : morphir.sdk.Set.Set[ComparableNode] => morphir.sdk.Basics.Bool)))(currentEdgesByNode)
              
              {
                val nextReachableNodes: morphir.sdk.Set.Set[ComparableNode] = morphir.sdk.Set.diff(morphir.sdk.List.foldl[Set[ComparableNode], Set[ComparableNode]](morphir.sdk.Set.union)(morphir.sdk.Set.empty[ComparableNode])(morphir.sdk.Dict.values(reachableEdges)))(reachableSoFar)
                
                if (morphir.sdk.Set.isEmpty(nextReachableNodes)) {
                  reachableSoFar
                } else {
                  collect(morphir.sdk.Set.union(reachableSoFar)(nextReachableNodes))(unreachableEdges)
                }
              }
            }
            
            collect(firstReachableNodes)(initialEdgesByNode)
          }
        }
    } : morphir.dependency.DAG.DAG[ComparableNode] => morphir.sdk.Set.Set[ComparableNode])
  
  def deleteNode[ComparableNode](
    comparableNode: ComparableNode
  ): morphir.dependency.DAG.DAG[ComparableNode] => morphir.dependency.DAG.DAG[ComparableNode] =
    ({
      case morphir.dependency.DAG.DAG(e) => 
        (morphir.dependency.DAG.DAG(morphir.sdk.Dict.remove(comparableNode)(e)) : morphir.dependency.DAG.DAG[ComparableNode])
    } : morphir.dependency.DAG.DAG[ComparableNode] => morphir.dependency.DAG.DAG[ComparableNode])
  
  def empty[ComparableNode]: morphir.dependency.DAG.DAG[ComparableNode] =
    (morphir.dependency.DAG.DAG(morphir.sdk.Dict.empty) : morphir.dependency.DAG.DAG[ComparableNode])
  
  def forwardTopologicalOrdering[ComparableNode](
    dag: morphir.dependency.DAG.DAG[ComparableNode]
  ): morphir.sdk.List.List[morphir.sdk.List.List[ComparableNode]] =
    morphir.sdk.List.reverse(morphir.dependency.DAG.backwardTopologicalOrdering(dag))
  
  def incomingEdges[ComparableNode](
    toNode: ComparableNode
  ): morphir.dependency.DAG.DAG[ComparableNode] => morphir.sdk.Set.Set[ComparableNode] =
    ({
      case morphir.dependency.DAG.DAG(edges) => 
        morphir.sdk.Set.fromList(morphir.sdk.List.filterMap(({
          case (fromNode, toNodes) => 
            if (morphir.sdk.Set.member(toNode)(toNodes)) {
              (morphir.sdk.Maybe.Just(fromNode) : morphir.sdk.Maybe.Maybe[ComparableNode])
            } else {
              (morphir.sdk.Maybe.Nothing : morphir.sdk.Maybe.Maybe[ComparableNode])
            }
        } : ((ComparableNode, morphir.sdk.Set.Set[ComparableNode])) => morphir.sdk.Maybe.Maybe[ComparableNode]))(morphir.sdk.Dict.toList(edges)))
    } : morphir.dependency.DAG.DAG[ComparableNode] => morphir.sdk.Set.Set[ComparableNode])
  
  def insertEdge[ComparableNode](
    from: ComparableNode
  )(
    to: ComparableNode
  ): morphir.dependency.DAG.DAG[ComparableNode] => morphir.sdk.Result.Result[morphir.dependency.DAG.CycleDetected[ComparableNode], morphir.dependency.DAG.DAG[ComparableNode]] =
    ({
      case morphir.dependency.DAG.DAG(edgesByNodes) => 
        if (morphir.sdk.Basics.equal(from)(to)) {
          (morphir.sdk.Result.Ok((morphir.dependency.DAG.DAG(((edges: morphir.sdk.Set.Set[ComparableNode]) =>
            morphir.sdk.Dict.insert(from)(morphir.sdk.Set.insert(to)(edges))(edgesByNodes))(morphir.sdk.Maybe.withDefault(morphir.sdk.Set.empty[ComparableNode])(morphir.sdk.Dict.get(from)(edgesByNodes)))) : morphir.dependency.DAG.DAG[ComparableNode])) : morphir.sdk.Result.Result[morphir.dependency.DAG.CycleDetected[ComparableNode], morphir.dependency.DAG.DAG[ComparableNode]])
        } else if (morphir.sdk.Set.member(from)(morphir.dependency.DAG.collectForwardReachableNodes(to)((morphir.dependency.DAG.DAG(edgesByNodes) : morphir.dependency.DAG.DAG[ComparableNode])))) {
          (morphir.sdk.Result.Err((morphir.dependency.DAG.CycleDetected(
            from,
            to
          ) : morphir.dependency.DAG.CycleDetected[ComparableNode])) : morphir.sdk.Result.Result[morphir.dependency.DAG.CycleDetected[ComparableNode], morphir.dependency.DAG.DAG[ComparableNode]])
        } else if (morphir.sdk.Set.member(to)(morphir.sdk.Maybe.withDefault(morphir.sdk.Set.empty[ComparableNode])(morphir.sdk.Dict.get(from)(edgesByNodes)))) {
          (morphir.sdk.Result.Ok((morphir.dependency.DAG.DAG(edgesByNodes) : morphir.dependency.DAG.DAG[ComparableNode])) : morphir.sdk.Result.Result[morphir.dependency.DAG.CycleDetected[ComparableNode], morphir.dependency.DAG.DAG[ComparableNode]])
        } else if (morphir.sdk.Dict.member(to)(edgesByNodes)) {
          (morphir.sdk.Result.Ok((morphir.dependency.DAG.DAG(((fromEdges: morphir.sdk.Set.Set[ComparableNode]) =>
            morphir.sdk.Dict.insert(from)(morphir.sdk.Set.insert(to)(fromEdges))(edgesByNodes))(morphir.sdk.Maybe.withDefault(morphir.sdk.Set.empty[ComparableNode])(morphir.sdk.Dict.get(from)(edgesByNodes)))) : morphir.dependency.DAG.DAG[ComparableNode])) : morphir.sdk.Result.Result[morphir.dependency.DAG.CycleDetected[ComparableNode], morphir.dependency.DAG.DAG[ComparableNode]])
        } else {
          (morphir.sdk.Result.Ok((morphir.dependency.DAG.DAG(morphir.sdk.Dict.insert(to)(morphir.sdk.Set.empty[ComparableNode])(((fromEdges: morphir.sdk.Set.Set[ComparableNode]) =>
            morphir.sdk.Dict.insert(from)(morphir.sdk.Set.insert(to)(fromEdges))(edgesByNodes))(morphir.sdk.Maybe.withDefault(morphir.sdk.Set.empty[ComparableNode])(morphir.sdk.Dict.get(from)(edgesByNodes))))) : morphir.dependency.DAG.DAG[ComparableNode])) : morphir.sdk.Result.Result[morphir.dependency.DAG.CycleDetected[ComparableNode], morphir.dependency.DAG.DAG[ComparableNode]])
        }
    } : morphir.dependency.DAG.DAG[ComparableNode] => morphir.sdk.Result.Result[morphir.dependency.DAG.CycleDetected[ComparableNode], morphir.dependency.DAG.DAG[ComparableNode]])
  
  def insertNode[ComparableNode](
    fromNode: ComparableNode
  )(
    toNodes: morphir.sdk.Set.Set[ComparableNode]
  ): morphir.dependency.DAG.DAG[ComparableNode] => morphir.sdk.Result.Result[morphir.dependency.DAG.CycleDetected[ComparableNode], morphir.dependency.DAG.DAG[ComparableNode]] =
    ({
      case morphir.dependency.DAG.DAG(edgesByNode) => 
        {
          def insertEdges(
            nodes: morphir.sdk.Set.Set[ComparableNode]
          )(
            d: morphir.dependency.DAG.DAG[ComparableNode]
          ): morphir.sdk.Result.Result[morphir.dependency.DAG.CycleDetected[ComparableNode], morphir.dependency.DAG.DAG[ComparableNode]] =
            morphir.sdk.List.foldl(((toNode: ComparableNode) =>
              ((dagResultSoFar: morphir.sdk.Result.Result[morphir.dependency.DAG.CycleDetected[ComparableNode], morphir.dependency.DAG.DAG[ComparableNode]]) =>
                morphir.sdk.Result.andThen(morphir.dependency.DAG.insertEdge(fromNode)(toNode))(dagResultSoFar))))((morphir.sdk.Result.Ok(d) : morphir.sdk.Result.Result[morphir.dependency.DAG.CycleDetected[ComparableNode], morphir.dependency.DAG.DAG[ComparableNode]]))(morphir.sdk.Set.toList(nodes))
          
          if (morphir.sdk.Dict.member(fromNode)(edgesByNode)) {
            insertEdges(toNodes)((morphir.dependency.DAG.DAG(edgesByNode) : morphir.dependency.DAG.DAG[ComparableNode]))
          } else {
            insertEdges(toNodes)((morphir.dependency.DAG.DAG(morphir.sdk.Dict.insert(fromNode)(morphir.sdk.Set.empty[ComparableNode])(edgesByNode)) : morphir.dependency.DAG.DAG[ComparableNode]))
          }
        }
    } : morphir.dependency.DAG.DAG[ComparableNode] => morphir.sdk.Result.Result[morphir.dependency.DAG.CycleDetected[ComparableNode], morphir.dependency.DAG.DAG[ComparableNode]])
  
  def outgoingEdges[ComparableNode](
    fromNode: ComparableNode
  ): morphir.dependency.DAG.DAG[ComparableNode] => morphir.sdk.Set.Set[ComparableNode] =
    ({
      case morphir.dependency.DAG.DAG(edges) => 
        morphir.sdk.Maybe.withDefault(morphir.sdk.Set.empty[ComparableNode])(morphir.sdk.Dict.get(fromNode)(edges))
    } : morphir.dependency.DAG.DAG[ComparableNode] => morphir.sdk.Set.Set[ComparableNode])
  
  def removeEdge[ComparableNode](
    from: ComparableNode
  )(
    to: ComparableNode
  ): morphir.dependency.DAG.DAG[ComparableNode] => morphir.dependency.DAG.DAG[ComparableNode] =
    ({
      case morphir.dependency.DAG.DAG(edgesByNode) => 
        (morphir.dependency.DAG.DAG(morphir.sdk.Dict.update(from)(morphir.sdk.Maybe.map(((set: morphir.sdk.Set.Set[ComparableNode]) =>
          morphir.sdk.Set.remove(to)(set))))(edgesByNode)) : morphir.dependency.DAG.DAG[ComparableNode])
    } : morphir.dependency.DAG.DAG[ComparableNode] => morphir.dependency.DAG.DAG[ComparableNode])
  
  def removeIncomingEdges[ComparableNode](
    comparableNode: ComparableNode
  )(
    dag: morphir.dependency.DAG.DAG[ComparableNode]
  ): morphir.dependency.DAG.DAG[ComparableNode] =
    morphir.sdk.List.foldl(((from: ComparableNode) =>
      ((g: morphir.dependency.DAG.DAG[ComparableNode]) =>
        morphir.dependency.DAG.removeEdge(from)(comparableNode)(g))))(dag)(morphir.sdk.Set.toList(morphir.dependency.DAG.incomingEdges(comparableNode)(dag)))
  
  def removeNode[ComparableNode](
    comparableNode: ComparableNode
  ): morphir.dependency.DAG.DAG[ComparableNode] => morphir.dependency.DAG.DAG[ComparableNode] =
    ({
      case morphir.dependency.DAG.DAG(edges) => 
        morphir.sdk.Dict.get(comparableNode)(edges) match {
          case morphir.sdk.Maybe.Nothing => 
            (morphir.dependency.DAG.DAG(edges) : morphir.dependency.DAG.DAG[ComparableNode])
          case morphir.sdk.Maybe.Just(_) => 
            morphir.dependency.DAG.deleteNode(comparableNode)(morphir.dependency.DAG.removeIncomingEdges(comparableNode)((morphir.dependency.DAG.DAG(edges) : morphir.dependency.DAG.DAG[ComparableNode])))
        }
    } : morphir.dependency.DAG.DAG[ComparableNode] => morphir.dependency.DAG.DAG[ComparableNode])
  
  def toList[ComparableNode]: morphir.dependency.DAG.DAG[ComparableNode] => morphir.sdk.List.List[(ComparableNode, morphir.sdk.Set.Set[ComparableNode])] =
    ({
      case morphir.dependency.DAG.DAG(dict) => 
        morphir.sdk.Dict.toList(dict)
    } : morphir.dependency.DAG.DAG[ComparableNode] => morphir.sdk.List.List[(ComparableNode, morphir.sdk.Set.Set[ComparableNode])])

}
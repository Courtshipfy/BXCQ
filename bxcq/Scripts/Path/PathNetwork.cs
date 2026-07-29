using System;
using System.Collections.Generic;
using System.Linq;
using Godot;

namespace BXCQ.PathSystem;

/// <summary>
/// Sparse Path Network: weld Path2D endpoints/samples into junctions, then Dijkstra on edges.
/// Built once (Ready); click pathfinding inserts temporary start/goal nodes.
/// </summary>
public sealed class PathNetwork
{
	private readonly List<Path2D> _paths;
	private readonly List<NetworkNode> _nodes;
	private readonly List<NetworkEdge> _edges;
	private readonly Dictionary<int, List<int>> _adjacency; // nodeId -> edgeIds

	public IReadOnlyList<Path2D> Paths => _paths;
	public IReadOnlyList<NetworkNode> Nodes => _nodes;
	public IReadOnlyList<NetworkEdge> Edges => _edges;

	public float WeldRadius { get; }
	public float WeldSampleSpacing { get; }

	private PathNetwork(
		List<Path2D> paths,
		List<NetworkNode> nodes,
		List<NetworkEdge> edges,
		float weldRadius,
		float weldSampleSpacing)
	{
		_paths = paths;
		_nodes = nodes;
		_edges = edges;
		WeldRadius = weldRadius;
		WeldSampleSpacing = weldSampleSpacing;
		_adjacency = BuildAdjacency(nodes, edges);
	}

	public static PathNetwork Build(
		IEnumerable<Path2D> pathNodes,
		float weldRadius = 24f,
		float weldSampleSpacing = 32f)
	{
		var paths = pathNodes.Where(p => p?.Curve != null && p.Curve.PointCount >= 2).ToList();
		if (paths.Count == 0)
		{
			return new PathNetwork(paths, new List<NetworkNode>(), new List<NetworkEdge>(), weldRadius, weldSampleSpacing);
		}

		var samples = CollectSamples(paths, weldSampleSpacing);
		var parent = Enumerable.Range(0, samples.Count).ToArray();

		int Find(int i)
		{
			while (parent[i] != i)
			{
				parent[i] = parent[parent[i]];
				i = parent[i];
			}

			return i;
		}

		void Union(int a, int b)
		{
			a = Find(a);
			b = Find(b);
			if (a != b)
			{
				parent[b] = a;
			}
		}

		var weldSquared = weldRadius * weldRadius;
		for (var i = 0; i < samples.Count; i++)
		{
			for (var j = i + 1; j < samples.Count; j++)
			{
				if (samples[i].World.DistanceSquaredTo(samples[j].World) <= weldSquared)
				{
					Union(i, j);
				}
			}
		}

		var clusters = new Dictionary<int, List<int>>();
		for (var i = 0; i < samples.Count; i++)
		{
			var root = Find(i);
			if (!clusters.TryGetValue(root, out var list))
			{
				list = new List<int>();
				clusters[root] = list;
			}

			list.Add(i);
		}

		var nodes = new List<NetworkNode>();
		// pathId -> (offset, nodeId) anchors on that walk path
		var anchorsByPath = new Dictionary<int, List<(float Offset, int NodeId)>>();

		var nextNodeId = 0;
		foreach (var memberIndices in clusters.Values)
		{
			var pathIdsInCluster = new HashSet<int>();
			var hasEndpoint = false;
			foreach (var idx in memberIndices)
			{
				var s = samples[idx];
				pathIdsInCluster.Add(s.PathId);
				var length = paths[s.PathId].Curve.GetBakedLength();
				if (s.Offset <= 0.5f || s.Offset >= length - 0.5f)
				{
					hasEndpoint = true;
				}
			}

			// Dense samples are weld probes only. Keep a node only if it is an
			// endpoint and/or a true junction (samples from 2+ Walk Paths).
			var isJunction = pathIdsInCluster.Count >= 2;
			if (!hasEndpoint && !isJunction)
			{
				continue;
			}

			var avg = Vector2.Zero;
			foreach (var idx in memberIndices)
			{
				avg += samples[idx].World;
			}

			avg /= memberIndices.Count;

			var node = new NetworkNode
			{
				Id = nextNodeId++,
				WorldPosition = avg,
			};
			nodes.Add(node);

			// One anchor per path in this cluster (average offsets if multiple samples).
			var offsetsByPath = new Dictionary<int, List<float>>();
			foreach (var idx in memberIndices)
			{
				var s = samples[idx];
				if (!offsetsByPath.TryGetValue(s.PathId, out var offs))
				{
					offs = new List<float>();
					offsetsByPath[s.PathId] = offs;
				}

				offs.Add(s.Offset);
			}

			foreach (var (pathId, offs) in offsetsByPath)
			{
				var offset = offs.Average();
				if (!anchorsByPath.TryGetValue(pathId, out var anchors))
				{
					anchors = new List<(float, int)>();
					anchorsByPath[pathId] = anchors;
				}

				anchors.Add((offset, node.Id));
			}
		}

		var edges = new List<NetworkEdge>();
		var nextEdgeId = 0;
		foreach (var (pathId, anchors) in anchorsByPath)
		{
			var ordered = anchors
				.GroupBy(a => a.NodeId)
				.Select(g => (Offset: g.Average(x => x.Offset), NodeId: g.Key))
				.OrderBy(a => a.Offset)
				.ToList();

			for (var i = 0; i < ordered.Count - 1; i++)
			{
				var a = ordered[i];
				var b = ordered[i + 1];
				if (Mathf.IsEqualApprox(a.Offset, b.Offset))
				{
					continue;
				}

				var edge = new NetworkEdge
				{
					Id = nextEdgeId++,
					PathId = pathId,
					NodeA = a.NodeId,
					NodeB = b.NodeId,
					OffsetA = a.Offset,
					OffsetB = b.Offset,
				};
				edges.Add(edge);
				nodes[a.NodeId].EdgeIds.Add(edge.Id);
				nodes[b.NodeId].EdgeIds.Add(edge.Id);
			}
		}

		return new PathNetwork(paths, nodes, edges, weldRadius, weldSampleSpacing);
	}

	public PathPose FindClosestPose(Vector2 worldPosition)
	{
		var bestPath = 0;
		var bestOffset = 0f;
		var bestDist = float.MaxValue;

		for (var i = 0; i < _paths.Count; i++)
		{
			var path = _paths[i];
			var curve = path.Curve;
			var local = path.ToLocal(worldPosition);
			var offset = curve.GetClosestOffset(local);
			var closestWorld = path.ToGlobal(curve.SampleBaked(offset));
			var dist = closestWorld.DistanceSquaredTo(worldPosition);
			if (dist < bestDist)
			{
				bestDist = dist;
				bestPath = i;
				bestOffset = offset;
			}
		}

		return new PathPose(bestPath, bestOffset);
	}

	public Vector2 PoseToWorld(PathPose pose)
	{
		var path = _paths[pose.PathId];
		return path.ToGlobal(path.Curve.SampleBaked(pose.Offset));
	}

	/// <summary>Project a world point onto the nearest Path Pose and return its world position.</summary>
	public Vector2 ProjectToNetwork(Vector2 worldPosition) => PoseToWorld(FindClosestPose(worldPosition));


	public Vector2 GetWorldTangent(PathPose pose)
	{
		var path = _paths[pose.PathId];
		var baked = path.Curve.SampleBakedWithRotation(pose.Offset);
		var tangent = (path.GlobalTransform * baked).X.Normalized();
		return tangent.LengthSquared() < 0.0001f ? Vector2.Right : tangent;
	}

	public bool TryGetEdge(int edgeId, out NetworkEdge edge)
	{
		foreach (var e in _edges)
		{
			if (e.Id == edgeId)
			{
				edge = e;
				return true;
			}
		}

		edge = null!;
		return false;
	}

	/// <summary>Edge whose offset interval contains the pose (with a small pad).</summary>
	public bool TryFindContainingEdge(PathPose pose, out NetworkEdge edge)
	{
		const float pad = 0.75f;
		NetworkEdge best = null!;
		var bestSpan = float.MaxValue;
		foreach (var e in _edges)
		{
			if (e.PathId != pose.PathId)
			{
				continue;
			}

			if (pose.Offset < e.OffsetA - pad || pose.Offset > e.OffsetB + pad)
			{
				continue;
			}

			if (e.Length < bestSpan)
			{
				bestSpan = e.Length;
				best = e;
			}
		}

		edge = best;
		return best != null;
	}

	/// <summary>World-space direction when leaving <paramref name="fromNodeId"/> along the edge.</summary>
	public Vector2 GetExitTangent(NetworkEdge edge, int fromNodeId)
	{
		const float sampleAlong = 4f;
		if (fromNodeId == edge.NodeA)
		{
			var o = Mathf.Min(edge.OffsetA + sampleAlong, edge.OffsetB);
			return GetWorldTangent(new PathPose(edge.PathId, o));
		}

		var oB = Mathf.Max(edge.OffsetB - sampleAlong, edge.OffsetA);
		return -GetWorldTangent(new PathPose(edge.PathId, oB));
	}

	public PathPose PoseAtNodeOnEdge(NetworkEdge edge, int nodeId) =>
		nodeId == edge.NodeA
			? new PathPose(edge.PathId, edge.OffsetA)
			: new PathPose(edge.PathId, edge.OffsetB);

	/// <summary>
	/// At a Junction, pick the outbound edge whose exit tangent best matches <paramref name="inputDir"/>.
	/// Soft-penalizes <paramref name="excludeEdgeId"/> so U-turns are possible but not preferred.
	/// </summary>
	public NetworkEdge ChooseForkEdge(int nodeId, Vector2 inputDir, int excludeEdgeId = -1)
	{
		if (nodeId < 0 || nodeId >= _nodes.Count)
		{
			return null!;
		}

		if (inputDir.LengthSquared() < 0.0001f)
		{
			return null!;
		}

		var input = inputDir.Normalized();
		NetworkEdge best = null!;
		var bestScore = float.NegativeInfinity;

		foreach (var edgeId in _nodes[nodeId].EdgeIds)
		{
			if (!TryGetEdge(edgeId, out var edge))
			{
				continue;
			}

			var exit = GetExitTangent(edge, nodeId);
			if (exit.LengthSquared() < 0.0001f)
			{
				continue;
			}

			var score = input.Dot(exit.Normalized());
			if (edge.Id == excludeEdgeId)
			{
				score -= 0.2f;
			}

			if (score > bestScore)
			{
				bestScore = score;
				best = edge;
			}
		}

		return best;
	}

	/// <summary>True if any graph node touches both given path ids (a weld Junction).</summary>
	public bool TryFindJunctionBetweenPaths(int pathA, int pathB, out NetworkNode junction)
	{
		foreach (var node in _nodes)
		{
			var hasA = false;
			var hasB = false;
			foreach (var edgeId in node.EdgeIds)
			{
				if (!TryGetEdge(edgeId, out var edge))
				{
					continue;
				}

				if (edge.PathId == pathA)
				{
					hasA = true;
				}

				if (edge.PathId == pathB)
				{
					hasB = true;
				}
			}

			if (hasA && hasB)
			{
				junction = node;
				return true;
			}
		}

		junction = null!;
		return false;
	}

	/// <summary>Shortest walk as a sequence of PathLegs along Walk Paths.</summary>
	public List<PathLeg> FindPath(PathPose start, PathPose goal)
	{
		if (_paths.Count == 0)
		{
			return new List<PathLeg>();
		}

		if (start.PathId == goal.PathId && Mathf.IsEqualApprox(start.Offset, goal.Offset))
		{
			return new List<PathLeg>();
		}

		// Working copy so temporary start/goal splits do not mutate the static graph.
		var workNodes = _nodes.Select(n => new NetworkNode
		{
			Id = n.Id,
			WorldPosition = n.WorldPosition,
			EdgeIds = new List<int>(n.EdgeIds),
		}).ToList();
		var workEdges = _edges.Select(e => e.Clone()).ToList();

		var startId = InsertPose(workNodes, workEdges, start);
		var goalId = InsertPose(workNodes, workEdges, goal);

		if (startId == goalId)
		{
			return new List<PathLeg>();
		}

		var adjacency = BuildAdjacency(workNodes, workEdges);
		var previousEdge = Dijkstra(workNodes, workEdges, adjacency, startId, goalId);
		if (!previousEdge.ContainsKey(goalId))
		{
			return new List<PathLeg>();
		}

		return ReconstructLegs(workEdges, previousEdge, startId, goalId);
	}

	private int InsertPose(List<NetworkNode> nodes, List<NetworkEdge> edges, PathPose pose)
	{
		const float snapEpsilon = 1.5f;
		pose = ClampPoseToPath(pose);

		// Already at an existing node on this path?
		foreach (var edge in edges)
		{
			if (edge.PathId != pose.PathId)
			{
				continue;
			}

			if (Mathf.Abs(pose.Offset - edge.OffsetA) <= snapEpsilon)
			{
				return edge.NodeA;
			}

			if (Mathf.Abs(pose.Offset - edge.OffsetB) <= snapEpsilon)
			{
				return edge.NodeB;
			}
		}

		NetworkEdge host = null!;
		foreach (var edge in edges)
		{
			if (edge.PathId != pose.PathId)
			{
				continue;
			}

			if (pose.Offset >= edge.OffsetA - 0.01f && pose.Offset <= edge.OffsetB + 0.01f)
			{
				host = edge;
				break;
			}
		}

		if (host == null)
		{
			// Fallback: nearest edge endpoint on this path.
			var bestNode = 0;
			var bestDist = float.MaxValue;
			foreach (var edge in edges)
			{
				if (edge.PathId != pose.PathId)
				{
					continue;
				}

				Consider(edge.NodeA, edge.OffsetA);
				Consider(edge.NodeB, edge.OffsetB);
			}

			return bestNode;

			void Consider(int nodeId, float offset)
			{
				var d = Mathf.Abs(offset - pose.Offset);
				if (d < bestDist)
				{
					bestDist = d;
					bestNode = nodeId;
				}
			}
		}

		var newId = nodes.Count;
		var world = PoseToWorld(pose);
		var newNode = new NetworkNode
		{
			Id = newId,
			WorldPosition = world,
		};
		nodes.Add(newNode);

		edges.Remove(host);
		nodes[host.NodeA].EdgeIds.Remove(host.Id);
		nodes[host.NodeB].EdgeIds.Remove(host.Id);

		var nextId = NextEdgeId(edges);
		var left = new NetworkEdge
		{
			Id = nextId,
			PathId = host.PathId,
			NodeA = host.NodeA,
			NodeB = newId,
			OffsetA = host.OffsetA,
			OffsetB = pose.Offset,
		};
		var right = new NetworkEdge
		{
			Id = nextId + 1,
			PathId = host.PathId,
			NodeA = newId,
			NodeB = host.NodeB,
			OffsetA = pose.Offset,
			OffsetB = host.OffsetB,
		};

		edges.Add(left);
		edges.Add(right);
		nodes[left.NodeA].EdgeIds.Add(left.Id);
		nodes[left.NodeB].EdgeIds.Add(left.Id);
		nodes[right.NodeA].EdgeIds.Add(right.Id);
		nodes[right.NodeB].EdgeIds.Add(right.Id);

		return newId;
	}

	private PathPose ClampPoseToPath(PathPose pose)
	{
		var length = _paths[pose.PathId].Curve.GetBakedLength();
		return pose with { Offset = Mathf.Clamp(pose.Offset, 0f, length) };
	}

	private static int NextEdgeId(List<NetworkEdge> edges)
	{
		var max = -1;
		foreach (var e in edges)
		{
			if (e.Id > max)
			{
				max = e.Id;
			}
		}

		return max + 1;
	}

	private static Dictionary<int, List<int>> BuildAdjacency(
		List<NetworkNode> nodes,
		List<NetworkEdge> edges)
	{
		var adj = new Dictionary<int, List<int>>();
		foreach (var node in nodes)
		{
			adj[node.Id] = new List<int>();
		}

		foreach (var edge in edges)
		{
			adj[edge.NodeA].Add(edge.Id);
			adj[edge.NodeB].Add(edge.Id);
		}

		return adj;
	}

	/// <returns>previousEdge[nodeId] = edge used to reach nodeId. Missing goal key means unreachable.</returns>
	private static Dictionary<int, int> Dijkstra(
		List<NetworkNode> nodes,
		List<NetworkEdge> edges,
		Dictionary<int, List<int>> adjacency,
		int startId,
		int goalId)
	{
		var edgeById = edges.ToDictionary(e => e.Id);
		var dist = new Dictionary<int, float>();
		var prevEdge = new Dictionary<int, int>();
		var visited = new HashSet<int>();

		foreach (var node in nodes)
		{
			dist[node.Id] = float.PositiveInfinity;
		}

		dist[startId] = 0f;
		var queue = new SortedSet<(float Dist, int NodeId)>(Comparer<(float, int)>.Create((a, b) =>
		{
			var cmp = a.Item1.CompareTo(b.Item1);
			return cmp != 0 ? cmp : a.Item2.CompareTo(b.Item2);
		}));
		queue.Add((0f, startId));

		while (queue.Count > 0)
		{
			var (d, u) = queue.Min;
			queue.Remove(queue.Min);
			if (!visited.Add(u))
			{
				continue;
			}

			if (u == goalId)
			{
				return prevEdge;
			}

			if (!adjacency.TryGetValue(u, out var edgeIds))
			{
				continue;
			}

			foreach (var edgeId in edgeIds)
			{
				var edge = edgeById[edgeId];
				var v = edge.OtherNode(u);
				var nd = d + edge.Length;
				if (nd + 0.0001f >= dist[v])
				{
					continue;
				}

				dist[v] = nd;
				prevEdge[v] = edgeId;
				queue.Add((nd, v));
			}
		}

		return prevEdge;
	}

	private static List<PathLeg> ReconstructLegs(
		List<NetworkEdge> edges,
		Dictionary<int, int> previousEdge,
		int startId,
		int goalId)
	{
		var edgeById = edges.ToDictionary(e => e.Id);
		var nodeChain = new List<int> { goalId };
		var current = goalId;
		while (current != startId)
		{
			if (!previousEdge.TryGetValue(current, out var edgeId))
			{
				return new List<PathLeg>();
			}

			var edge = edgeById[edgeId];
			current = edge.OtherNode(current);
			nodeChain.Add(current);
		}

		nodeChain.Reverse();

		var legs = new List<PathLeg>();
		for (var i = 0; i < nodeChain.Count - 1; i++)
		{
			var fromNode = nodeChain[i];
			var toNode = nodeChain[i + 1];
			NetworkEdge connecting = null!;
			foreach (var edge in edges)
			{
				if ((edge.NodeA == fromNode && edge.NodeB == toNode) ||
					(edge.NodeB == fromNode && edge.NodeA == toNode))
				{
					connecting = edge;
					break;
				}
			}

			if (connecting == null)
			{
				continue;
			}

			float fromOffset;
			float toOffset;
			if (connecting.NodeA == fromNode)
			{
				fromOffset = connecting.OffsetA;
				toOffset = connecting.OffsetB;
			}
			else
			{
				fromOffset = connecting.OffsetB;
				toOffset = connecting.OffsetA;
			}

			if (legs.Count > 0 && legs[^1].PathId == connecting.PathId)
			{
				// Merge consecutive slides on the same Walk Path.
				var prev = legs[^1];
				legs[^1] = new PathLeg(prev.PathId, prev.FromOffset, toOffset);
			}
			else
			{
				legs.Add(new PathLeg(connecting.PathId, fromOffset, toOffset));
			}
		}

		return legs;
	}

	private static List<(int PathId, float Offset, Vector2 World)> CollectSamples(
		List<Path2D> paths,
		float sampleSpacing)
	{
		var samples = new List<(int PathId, float Offset, Vector2 World)>();
		for (var pathId = 0; pathId < paths.Count; pathId++)
		{
			var path = paths[pathId];
			var curve = path.Curve;
			var length = curve.GetBakedLength();
			if (length <= 0.01f)
			{
				continue;
			}

			AddSample(pathId, 0f);
			for (var o = sampleSpacing; o < length; o += sampleSpacing)
			{
				AddSample(pathId, o);
			}

			AddSample(pathId, length);
		}

		return samples;

		void AddSample(int pathId, float offset)
		{
			var path = paths[pathId];
			var world = path.ToGlobal(path.Curve.SampleBaked(offset));
			samples.Add((pathId, offset, world));
		}
	}
}

public sealed class NetworkNode
{
	public required int Id { get; init; }
	public Vector2 WorldPosition { get; set; }
	public List<int> EdgeIds { get; init; } = new();
}

public sealed class NetworkEdge
{
	public required int Id { get; set; }
	public required int PathId { get; init; }
	public required int NodeA { get; init; }
	public required int NodeB { get; init; }
	public required float OffsetA { get; init; }
	public required float OffsetB { get; init; }
	public float Length => OffsetB - OffsetA;

	public int OtherNode(int nodeId) => nodeId == NodeA ? NodeB : NodeA;

	public NetworkEdge Clone() => new()
	{
		Id = Id,
		PathId = PathId,
		NodeA = NodeA,
		NodeB = NodeB,
		OffsetA = OffsetA,
		OffsetB = OffsetB,
	};
}

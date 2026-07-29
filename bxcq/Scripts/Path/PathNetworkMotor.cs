using System.Collections.Generic;
using Godot;

namespace BXCQ.PathSystem;

/// <summary>
/// Shared Path Network motor for click shortest-path + WASD tangent / Junction forks.
/// Used by PlayerController; does not own a Node.
/// </summary>
public sealed class PathNetworkMotor
{
	private readonly PathNetwork _network;
	private readonly List<PathLeg> _legs = new();
	private int _legIndex = -1;
	private int _activeEdgeId = -1;
	private int _arrivedViaEdgeId = -1;
	private PathPose _pose;
	private bool _isMoving;

	public float MoveSpeed { get; set; } = 220f;
	public float ArrivalThreshold { get; set; } = 6f;

	public PathPose CurrentPose => _pose;
	public bool IsMoving => _isMoving;
	public bool HasClickRoute => _legIndex >= 0 && _legIndex < _legs.Count;
	public PathNetwork Network => _network;
	public int ClickRouteLegCount => HasClickRoute ? _legs.Count - _legIndex : 0;

	public PathNetworkMotor(PathNetwork network)
	{
		_network = network;
	}

	public void SnapToWorld(Vector2 worldPosition)
	{
		ClearClickRoute();
		_pose = _network.FindClosestPose(worldPosition);
		_arrivedViaEdgeId = -1;
		RememberContainingEdge();
		_isMoving = false;
	}

	public Vector2 WorldPosition => _network.PoseToWorld(_pose);
	public Vector2 FacingTangent => _network.GetWorldTangent(_pose);

	public void SetClickGoal(Vector2 worldPosition)
	{
		var goal = _network.FindClosestPose(worldPosition);
		_legs.Clear();
		_legs.AddRange(_network.FindPath(_pose, goal));
		_legIndex = _legs.Count > 0 ? 0 : -1;
		_arrivedViaEdgeId = -1;
		if (_legIndex < 0)
		{
			_pose = goal;
			RememberContainingEdge();
			_isMoving = false;
		}
	}

	/// <summary>Route length in baked offset units (remaining legs).</summary>
	public float RemainingRouteLength()
	{
		if (!HasClickRoute)
		{
			return 0f;
		}

		var total = 0f;
		for (var i = _legIndex; i < _legs.Count; i++)
		{
			total += _legs[i].Length;
		}

		return total;
	}

	public void ClearClickRoute()
	{
		_legs.Clear();
		_legIndex = -1;
	}

	/// <summary>
	/// Advance one physics tick. Returns whether pose changed.
	/// Keyboard input non-zero cancels click route.
	/// </summary>
	public bool Tick(Vector2 keyboardInput, float dt)
	{
		if (keyboardInput.LengthSquared() > 0.01f)
		{
			ClearClickRoute();
			return TickKeyboard(keyboardInput, dt);
		}

		if (HasClickRoute)
		{
			return TickClick(dt);
		}

		_isMoving = false;
		return false;
	}

	private bool TickKeyboard(Vector2 input, float dt)
	{
		if (!EnsureActiveEdge() || !_network.TryGetEdge(_activeEdgeId, out var edge))
		{
			_isMoving = false;
			return false;
		}

		if (TryGetNearbyNode(edge, out var nodeId))
		{
			var chosen = _network.ChooseForkEdge(nodeId, input, _arrivedViaEdgeId);
			if (chosen != null)
			{
				if (chosen.Id != edge.Id)
				{
					TransferOntoEdge(chosen, nodeId);
					_arrivedViaEdgeId = edge.Id;
					edge = chosen;
					_activeEdgeId = edge.Id;
				}
				else
				{
					_arrivedViaEdgeId = -1;
				}
			}
		}

		var tangent = _network.GetWorldTangent(_pose);
		var along = input.Dot(tangent);
		if (Mathf.Abs(along) < 0.08f && Mathf.Abs(input.X) > 0.08f)
		{
			along = Mathf.Abs(tangent.X) > 0.15f
				? input.X * Mathf.Sign(tangent.X)
				: input.X;
		}

		if (Mathf.Abs(along) < 0.04f)
		{
			_isMoving = false;
			return false;
		}

		var step = Mathf.Sign(along) * MoveSpeed * dt;
		var nextOffset = _pose.Offset + step;
		var hitNode = false;

		if (nextOffset <= edge.OffsetA)
		{
			nextOffset = edge.OffsetA;
			hitNode = true;
			_arrivedViaEdgeId = edge.Id;
		}
		else if (nextOffset >= edge.OffsetB)
		{
			nextOffset = edge.OffsetB;
			hitNode = true;
			_arrivedViaEdgeId = edge.Id;
		}

		_pose = new PathPose(edge.PathId, nextOffset);
		_isMoving = true;

		if (hitNode && TryGetNearbyNode(edge, out var endNode))
		{
			var chosen = _network.ChooseForkEdge(endNode, input, _arrivedViaEdgeId);
			if (chosen != null && chosen.Id != edge.Id)
			{
				TransferOntoEdge(chosen, endNode);
			}
		}

		return true;
	}

	private bool TickClick(float dt)
	{
		var leg = _legs[_legIndex];
		var remaining = leg.ToOffset - _pose.Offset;

		if (_pose.PathId != leg.PathId)
		{
			_pose = new PathPose(leg.PathId, leg.FromOffset);
			remaining = leg.ToOffset - _pose.Offset;
		}

		if (Mathf.Abs(remaining) <= ArrivalThreshold)
		{
			_pose = new PathPose(leg.PathId, leg.ToOffset);
			RememberContainingEdge();
			_legIndex++;
			if (_legIndex >= _legs.Count)
			{
				ClearClickRoute();
				_isMoving = false;
			}
			else
			{
				_isMoving = true;
			}

			return true;
		}

		var step = MoveSpeed * dt;
		var nextOffset = _pose.Offset + Mathf.Sign(remaining) * step;
		if (Mathf.Sign(leg.ToOffset - nextOffset) != Mathf.Sign(remaining) &&
			Mathf.Abs(leg.ToOffset - nextOffset) > 0.001f)
		{
			nextOffset = leg.ToOffset;
		}

		_pose = new PathPose(leg.PathId, nextOffset);
		RememberContainingEdge();
		_isMoving = true;
		return true;
	}

	private void TransferOntoEdge(NetworkEdge edge, int nodeId)
	{
		_pose = _network.PoseAtNodeOnEdge(edge, nodeId);
		var nudge = ArrivalThreshold + 2f;
		if (nodeId == edge.NodeA)
		{
			_pose = new PathPose(edge.PathId, Mathf.Min(edge.OffsetA + nudge, edge.OffsetB));
		}
		else
		{
			_pose = new PathPose(edge.PathId, Mathf.Max(edge.OffsetB - nudge, edge.OffsetA));
		}

		_activeEdgeId = edge.Id;
	}

	private bool TryGetNearbyNode(NetworkEdge edge, out int nodeId)
	{
		if (Mathf.Abs(_pose.Offset - edge.OffsetA) <= ArrivalThreshold)
		{
			nodeId = edge.NodeA;
			return true;
		}

		if (Mathf.Abs(_pose.Offset - edge.OffsetB) <= ArrivalThreshold)
		{
			nodeId = edge.NodeB;
			return true;
		}

		nodeId = -1;
		return false;
	}

	private bool EnsureActiveEdge()
	{
		if (_activeEdgeId >= 0 &&
			_network.TryGetEdge(_activeEdgeId, out var edge) &&
			edge.PathId == _pose.PathId &&
			_pose.Offset >= edge.OffsetA - 1f &&
			_pose.Offset <= edge.OffsetB + 1f)
		{
			return true;
		}

		return RememberContainingEdge();
	}

	private bool RememberContainingEdge()
	{
		if (_network.TryFindContainingEdge(_pose, out var edge))
		{
			_activeEdgeId = edge.Id;
			return true;
		}

		_activeEdgeId = -1;
		return false;
	}
}

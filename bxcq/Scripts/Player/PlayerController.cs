using Godot;
using BXCQ.GameInput;
using BXCQ.Interaction;
using BXCQ.PathSystem;

namespace BXCQ.Player;

public partial class PlayerController : CharacterBody2D
{
	private const uint InteractableCollisionMask = 2;

	[Export] public float MoveSpeed { get; set; } = 220f;
	[Export] public float ArrivalThreshold { get; set; } = 6f;
	[Export] public float InteractRangeX { get; set; } = 72f;
	/// <summary>After path-walk arrival, allow Interact if within this distance of the target.</summary>
	[Export] public float InteractArriveDistance { get; set; } = 96f;
	[Export] public NodePath InputReaderPath { get; set; } = "../MovementInputReader";
	[Export] public NodePath PathNetworkPath { get; set; } = "../PathNetwork";

	private Area2D _interactionArea = null!;
	private Node2D _visual = null!;
	private AnimationPlayer _animationPlayer = null!;
	private MovementInputReader _inputReader = null!;
	private PathNetworkMotor _motor = null!;
	private GameState _gameState = null!;
	private PlayerMoveState _previousMoveState = PlayerMoveState.Idle;
	private IInteractable _pendingInteractable = null!;
	private bool _hasPendingInteractable;

	public Area2D InteractionArea => _interactionArea;
	public PlayerMoveState MoveState { get; private set; } = PlayerMoveState.Idle;
	public Vector2 FacingDirection { get; private set; } = Vector2.Right;
	public string LastInteractionName { get; private set; } = "-";
	public bool UsesPathNetwork => _motor != null;
	public bool HasClickRoute => _motor?.HasClickRoute ?? false;
	public int CurrentPathId => _motor?.CurrentPose.PathId ?? -1;

	public override void _Ready()
	{
		MotionMode = MotionModeEnum.Floating;
		_interactionArea = GetNode<Area2D>("InteractionArea");
		_visual = GetNode<Node2D>("Visual");
		_animationPlayer = GetNode<AnimationPlayer>("AnimationPlayer");
		_inputReader = GetNode<MovementInputReader>(InputReaderPath);
		_gameState = GetNode<GameState>("/root/GameState");
		AddToGroup("player");

		var host = GetNodeOrNull<PathNetworkHost>(PathNetworkPath);
		if (host?.Network == null)
		{
			GD.PushError($"PlayerController: PathNetwork missing at '{PathNetworkPath}'. Path movement required.");
			return;
		}

		_motor = new PathNetworkMotor(host.Network)
		{
			MoveSpeed = MoveSpeed,
			ArrivalThreshold = ArrivalThreshold,
		};
		_motor.SnapToWorld(GlobalPosition);
		ApplyMotorPose(updateFacing: true);
		ApplyFacingToVisual();
		PlayMoveAnimation(PlayerMoveState.Idle);
		GD.Print("Path Network movement ready");
	}

	/// <summary>Called by LocationScene after spawn markers move the player.</summary>
	public void SnapToPathNetwork()
	{
		if (_motor == null)
		{
			return;
		}

		_motor.SnapToWorld(GlobalPosition);
		ApplyMotorPose(updateFacing: true);
	}

	public override void _Input(InputEvent @event)
	{
		if (_motor == null)
		{
			return;
		}

		if (_gameState.IsDialogueBlocking)
		{
			return;
		}

		if (@event.IsActionPressed("click_move") &&
			@event is InputEventMouseButton { ButtonIndex: MouseButton.Left })
		{
			HandlePrimaryClick(GetGlobalMousePosition());
			GetViewport().SetInputAsHandled();
			return;
		}

		if (@event.IsActionPressed("click_interact") &&
			@event is InputEventMouseButton { ButtonIndex: MouseButton.Right })
		{
			var hit = PickInteractableAt(GetGlobalMousePosition());
			if (hit != null)
			{
				RequestInteraction(hit);
			}

			GetViewport().SetInputAsHandled();
		}
	}

	public override void _PhysicsProcess(double delta)
	{
		if (_motor == null)
		{
			Velocity = Vector2.Zero;
			return;
		}

		if (_gameState.IsDialogueBlocking)
		{
			_motor.ClearClickRoute();
			_inputReader.ClearClickTarget();
			ClearPendingInteractable();
			Velocity = Vector2.Zero;
			UpdateMoveStateAndFacing(false, FacingDirection);
			return;
		}

		_motor.MoveSpeed = MoveSpeed;
		_motor.ArrivalThreshold = ArrivalThreshold;

		var intent = _inputReader.CurrentIntent;
		if (intent.Source == MovementInputSource.Keyboard)
		{
			ClearPendingInteractable();
			_motor.ClearClickRoute();
			_inputReader.ClearClickTarget();
		}

		var hadClickRoute = _motor.HasClickRoute;
		var keyboard = intent.Source == MovementInputSource.Keyboard
			? intent.Direction
			: Vector2.Zero;

		_motor.Tick(keyboard, (float)delta);
		ApplyMotorPose(updateFacing: _motor.IsMoving);

		if (hadClickRoute && !_motor.HasClickRoute)
		{
			_inputReader.ClearClickTarget();
		}

		Velocity = Vector2.Zero;
		UpdateMoveStateAndFacing(_motor.IsMoving, _motor.FacingTangent);

		if (_hasPendingInteractable && IsCloseEnoughToInteract(_pendingInteractable))
		{
			TryCompletePendingInteraction(forceIfPending: true);
		}
		else if (_hasPendingInteractable && hadClickRoute && !_motor.HasClickRoute)
		{
			if (IsCloseEnoughToInteract(_pendingInteractable))
			{
				TryCompletePendingInteraction(forceIfPending: true);
			}
			else
			{
				GD.Print("Smart interact: arrived on path but still too far — cancelled");
				ClearPendingInteractable();
			}
		}
	}

	private void ApplyMotorPose(bool updateFacing)
	{
		GlobalPosition = _motor.WorldPosition;
		if (updateFacing)
		{
			FacingDirection = _motor.FacingTangent;
			ApplyFacingToVisual();
		}
	}

	private void HandlePrimaryClick(Vector2 worldPosition)
	{
		var hit = PickInteractableAt(worldPosition);
		var hitName = hit?.DisplayName ?? "none";
		GD.Print($"click at {worldPosition} hit={hitName}");
		if (hit != null)
		{
			RequestInteraction(hit);
			return;
		}

		RequestMoveTo(worldPosition);
	}

	/// <summary>Starts path-constrained movement toward a world-space click target.</summary>
	public bool RequestMoveTo(Vector2 worldPosition)
	{
		if (_motor == null || _gameState.IsDialogueBlocking)
		{
			return false;
		}

		ClearPendingInteractable();
		_motor.SetClickGoal(worldPosition);
		_inputReader.SetClickTarget(worldPosition);
		return true;
	}

	/// <summary>Godot-facing command seam for interaction requests from input adapters.</summary>
	public bool RequestInteractionNode(Node target) =>
		target is IInteractable interactable && RequestInteraction(interactable);

	private bool RequestInteraction(IInteractable target)
	{
		if (!target.CanInteract(this))
		{
			return false;
		}

		if (IsCloseEnoughToInteract(target))
		{
			CompleteInteraction(target);
			return true;
		}

		var preferred = target.GetInteractionPoint(this);
		var approachOnPath = _motor.Network.ProjectToNetwork(preferred);
		_pendingInteractable = target;
		_hasPendingInteractable = true;
		_motor.SetClickGoal(approachOnPath);
		_inputReader.SetClickTarget(approachOnPath);

		GD.Print(
			$"Smart interact [{target.DisplayName}]: preferred={preferred} → path={approachOnPath} " +
			$"legs≈{_motor.ClickRouteLegCount} routeLen≈{_motor.RemainingRouteLength():F0}");
		return true;
	}

	private void TryCompletePendingInteraction(bool forceIfPending)
	{
		if (!_hasPendingInteractable)
		{
			return;
		}

		if (!forceIfPending && !IsCloseEnoughToInteract(_pendingInteractable))
		{
			return;
		}

		if (!_pendingInteractable.CanInteract(this))
		{
			ClearPendingInteractable();
			return;
		}

		CompleteInteraction(_pendingInteractable);
	}

	private void CompleteInteraction(IInteractable target)
	{
		_inputReader.ClearClickTarget();
		_motor.ClearClickRoute();
		ClearPendingInteractable();

		target.PrepareInteraction(this);
		target.Interact(this);
		LastInteractionName = target.DisplayName;
	}

	/// <summary>Turn to face a world point on the X axis.</summary>
	public void FaceToward(Vector2 worldPoint)
	{
		var dx = worldPoint.X - GlobalPosition.X;
		if (Mathf.Abs(dx) < 1f)
		{
			return;
		}

		FacingDirection = dx >= 0f ? Vector2.Right : Vector2.Left;
		ApplyFacingToVisual();
	}

	private void ClearPendingInteractable()
	{
		_hasPendingInteractable = false;
		_pendingInteractable = null!;
	}

	private bool IsCloseEnoughToInteract(IInteractable target)
	{
		if (IsInInteractionRange(target))
		{
			return true;
		}

		if (target is not Node2D node)
		{
			return false;
		}

		return GlobalPosition.DistanceTo(node.GlobalPosition) <= InteractArriveDistance;
	}

	private bool IsInInteractionRange(IInteractable target)
	{
		if (target is not Node2D)
		{
			return false;
		}

		if (target is Area2D area)
		{
			foreach (var overlapping in _interactionArea.GetOverlappingAreas())
			{
				if (overlapping == area)
				{
					return true;
				}
			}
		}

		if (target is Node2D node)
		{
			return Mathf.Abs(node.GlobalPosition.X - GlobalPosition.X) <= InteractRangeX &&
				Mathf.Abs(node.GlobalPosition.Y - GlobalPosition.Y) <= InteractArriveDistance;
		}

		return false;
	}

	private IInteractable PickInteractableAt(Vector2 worldPosition)
	{
		var space = GetWorld2D().DirectSpaceState;
		var query = new PhysicsPointQueryParameters2D
		{
			Position = worldPosition,
			CollideWithAreas = true,
			CollideWithBodies = false,
			CollisionMask = InteractableCollisionMask,
		};

		foreach (var hit in space.IntersectPoint(query))
		{
			var collider = hit["collider"].AsGodotObject();
			if (collider is IInteractable interactable)
			{
				return interactable;
			}

			if (collider is Node node && node.GetParent() is IInteractable parentInteractable)
			{
				return parentInteractable;
			}
		}

		foreach (var node in GetTree().GetNodesInGroup("interactables"))
		{
			if (node is not Node2D visual || node is not IInteractable interactable)
			{
				continue;
			}

			if (IsPointNearInteractable(visual, worldPosition))
			{
				return interactable;
			}
		}

		return null!;
	}

	private static bool IsPointNearInteractable(Node2D node, Vector2 worldPosition)
	{
		var shapeNode = node.GetNodeOrNull<CollisionShape2D>("CollisionShape2D");
		if (shapeNode?.Shape is RectangleShape2D rect)
		{
			var half = rect.Size * 0.5f * shapeNode.Scale.Abs();
			var center = shapeNode.GlobalPosition;
			return worldPosition.X >= center.X - half.X &&
				worldPosition.X <= center.X + half.X &&
				worldPosition.Y >= center.Y - half.Y &&
				worldPosition.Y <= center.Y + half.Y;
		}

		return Mathf.Abs(worldPosition.X - node.GlobalPosition.X) <= 40f &&
			Mathf.Abs(worldPosition.Y - node.GlobalPosition.Y) <= 48f;
	}

	private void UpdateMoveStateAndFacing(bool moving, Vector2 tangent)
	{
		MoveState = moving ? PlayerMoveState.Walking : PlayerMoveState.Idle;

		if (moving)
		{
			FacingDirection = tangent.LengthSquared() > 0.0001f ? tangent.Normalized() : FacingDirection;
			ApplyFacingToVisual();
		}

		if (MoveState != _previousMoveState)
		{
			PlayMoveAnimation(MoveState);
			_previousMoveState = MoveState;
		}
	}

	private void PlayMoveAnimation(PlayerMoveState state)
	{
		var animationName = state == PlayerMoveState.Walking ? "walk" : "idle";
		if (_animationPlayer.CurrentAnimation == animationName)
		{
			return;
		}

		_animationPlayer.Play(animationName);
	}

	private void ApplyFacingToVisual()
	{
		if (Mathf.Abs(FacingDirection.X) < 0.01f)
		{
			return;
		}

		var scale = _visual.Scale;
		scale.X = FacingDirection.X >= 0f ? 1f : -1f;
		_visual.Scale = scale;
	}
}

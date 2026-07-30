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
	private SmartInteractController _smartInteract = null!;
	private GameState _gameState = null!;
	private PlayerMoveState _previousMoveState = PlayerMoveState.Idle;

	public Area2D InteractionArea => _interactionArea;
	public PlayerMoveState MoveState { get; private set; } = PlayerMoveState.Idle;
	public Vector2 FacingDirection { get; private set; } = Vector2.Right;
	public string LastInteractionName { get; private set; } = "-";
	public bool UsesPathNetwork => _motor != null;
	public bool HasClickRoute => _motor?.HasClickRoute ?? false;
	public int CurrentPathId => _motor?.CurrentPose.PathId ?? -1;
	public string MovementIntentDescription => _motor?.CurrentIntent.Describe() ?? MovementIntent.None.Describe();

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
		if (host == null)
		{
			GD.PushError($"PlayerController: PathNetwork missing at '{PathNetworkPath}'. Path movement required.");
			return;
		}

		_motor = host.CreateMotor();
		_motor.MoveSpeed = MoveSpeed;
		_motor.ArrivalThreshold = ArrivalThreshold;
		_smartInteract = new SmartInteractController(this, _interactionArea, _motor);
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
			_smartInteract.Cancel();
			Velocity = Vector2.Zero;
			UpdateMoveStateAndFacing(false, FacingDirection);
			return;
		}

		_motor.MoveSpeed = MoveSpeed;
		_motor.ArrivalThreshold = ArrivalThreshold;

		var intent = _inputReader.CurrentIntent;
		if (intent.Source == MovementInputSource.Keyboard)
		{
			_smartInteract.Cancel();
		}

		var hadClickRoute = _motor.HasClickRoute;
		_motor.Tick(intent, (float)delta);
		ApplyMotorPose(updateFacing: _motor.IsMoving);

		Velocity = Vector2.Zero;
		UpdateMoveStateAndFacing(_motor.IsMoving, _motor.FacingTangent);
		_smartInteract.Tick(hadClickRoute);
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

		_smartInteract.Cancel();
		_motor.SetClickGoal(worldPosition);
		return true;
	}

	/// <summary>Godot-facing command seam for interaction requests from input adapters.</summary>
	public bool RequestInteractionNode(Node target) =>
		target is IInteractable interactable && RequestInteraction(interactable);

	private bool RequestInteraction(IInteractable target)
	{
		return _smartInteract.Request(target);
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

	internal void RecordInteraction(string displayName)
	{
		LastInteractionName = displayName;
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

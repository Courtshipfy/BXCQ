using Godot;

namespace BXCQ.GameInput;

public partial class MovementInputReader : Node2D
{
	private Vector2? _clickTarget;

	public MovementIntent CurrentIntent { get; private set; } = MovementIntent.None;

	public void SetClickTarget(Vector2 worldPosition)
	{
		_clickTarget = worldPosition;
	}

	public void ClearClickTarget()
	{
		_clickTarget = null;
		if (CurrentIntent.Source == MovementInputSource.Click)
		{
			CurrentIntent = MovementIntent.None;
		}
	}

	public override void _Process(double delta)
	{
		// Full 2D for Path Network Junction forks (W/S matter at branches).
		var keyboardDirection = Input.GetVector("move_left", "move_right", "move_up", "move_down");
		if (keyboardDirection.LengthSquared() > 0.0001f)
		{
			_clickTarget = null;
			CurrentIntent = MovementIntent.FromKeyboard(keyboardDirection);
			return;
		}

		if (_clickTarget is Vector2 target)
		{
			CurrentIntent = MovementIntent.FromClick(target);
			return;
		}

		CurrentIntent = MovementIntent.None;
	}
}

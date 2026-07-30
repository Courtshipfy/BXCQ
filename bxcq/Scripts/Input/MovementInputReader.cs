using Godot;

namespace BXCQ.GameInput;

public partial class MovementInputReader : Node2D
{
	public MovementIntent CurrentIntent { get; private set; } = MovementIntent.None;

	public override void _Process(double delta)
	{
		// Full 2D for Path Network Junction forks (W/S matter at branches).
		var keyboardDirection = Input.GetVector("move_left", "move_right", "move_up", "move_down");
		if (keyboardDirection.LengthSquared() > 0.0001f)
		{
			CurrentIntent = MovementIntent.FromKeyboard(keyboardDirection);
			return;
		}

		CurrentIntent = MovementIntent.None;
	}
}

using Godot;

namespace BXCQ.GameInput;

public enum MovementInputSource
{
	None,
	Keyboard,
	Click,
}

public readonly struct MovementIntent
{
	public Vector2 Direction { get; init; }
	public Vector2? ClickTarget { get; init; }
	public MovementInputSource Source { get; init; }

	public bool HasDirection => Direction.LengthSquared() > 0.0001f;
	public bool HasClickTarget => ClickTarget.HasValue;

	public static MovementIntent None => new() { Source = MovementInputSource.None };

	public static MovementIntent FromKeyboard(Vector2 direction) =>
		new()
		{
			Direction = direction,
			Source = MovementInputSource.Keyboard,
		};

	public static MovementIntent FromClick(Vector2 worldPosition) =>
		new()
		{
			ClickTarget = worldPosition,
			Source = MovementInputSource.Click,
		};

	public string Describe()
	{
		return Source switch
		{
			MovementInputSource.Keyboard =>
				$"WASD ({Direction.X:F2}, {Direction.Y:F2})",
			MovementInputSource.Click =>
				$"Click ({ClickTarget!.Value.X:F0}, {ClickTarget.Value.Y:F0})",
			_ => "Idle",
		};
	}
}

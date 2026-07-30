using Godot;

namespace BXCQ.Interaction;

public readonly record struct InteractionPlan(bool IsAvailable, Vector2 ApproachPoint)
{
	public static InteractionPlan Unavailable => new(false, Vector2.Zero);

	public static InteractionPlan ApproachFromHorizontal(
		Node2D target,
		Vector2 playerPosition,
		float approachOffsetX)
	{
		var side = playerPosition.X <= target.GlobalPosition.X ? -1f : 1f;
		return new InteractionPlan(
			true,
			new Vector2(target.GlobalPosition.X + side * approachOffsetX, target.GlobalPosition.Y));
	}
}

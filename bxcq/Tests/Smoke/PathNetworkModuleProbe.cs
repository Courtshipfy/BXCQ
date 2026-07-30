using Godot;
using BXCQ.GameInput;
using BXCQ.PathSystem;

namespace BXCQ.Tests;

/// <summary>Focused in-process probe for the Path Network movement interface.</summary>
public partial class PathNetworkModuleProbe : Node
{
	public string FailureMessage { get; private set; } = "";

	public bool Run()
	{
		var mainPath = CreatePath(new Vector2(0f, 0f), new Vector2(200f, 0f));
		var branchPath = CreatePath(new Vector2(100f, 0f), new Vector2(100f, -120f));
		var network = PathNetwork.Build(new[] { mainPath, branchPath }, 5f, 20f);
		var motor = new PathNetworkMotor(network)
		{
			MoveSpeed = 120f,
			ArrivalThreshold = 2f,
		};

		motor.SnapToWorld(new Vector2(5f, 0f));
		motor.SetClickGoal(new Vector2(195f, 0f));
		for (var i = 0; i < 180 && motor.HasClickRoute; i++)
		{
			motor.Tick(MovementIntent.None, 1f / 60f);
		}

		if (motor.HasClickRoute || motor.WorldPosition.DistanceTo(new Vector2(195f, 0f)) > 8f)
		{
			FailureMessage = $"click route failed: pose={motor.CurrentPose} world={motor.WorldPosition}";
			return false;
		}

		motor.SnapToWorld(new Vector2(100f, 0f));
		for (var i = 0; i < 40; i++)
		{
			motor.Tick(MovementIntent.FromKeyboard(Vector2.Up), 1f / 60f);
		}

		if (motor.CurrentPose.PathId != 1 || motor.WorldPosition.Y > -20f)
		{
			FailureMessage = $"junction choice failed: pose={motor.CurrentPose} world={motor.WorldPosition}";
			return false;
		}

		return true;
	}

	private static Path2D CreatePath(Vector2 start, Vector2 end)
	{
		var curve = new Curve2D();
		curve.AddPoint(start);
		curve.AddPoint(end);
		return new Path2D { Curve = curve };
	}
}

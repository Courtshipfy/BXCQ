using Godot;
using BXCQ.PathSystem;

namespace BXCQ.Debugging;

/// <summary>draws all Walk Paths and welded junction nodes from a PathNetworkHost.</summary>
public partial class PathNetworkGizmoDrawer : Node2D
{
	[Export] public NodePath NetworkHostPath { get; set; } = "../PathNetwork";
	[Export] public Color PathColor { get; set; } = new(0.95f, 0.75f, 0.25f, 0.9f);
	[Export] public Color BranchColor { get; set; } = new(0.45f, 0.8f, 0.95f, 0.9f);
	[Export] public Color JunctionColor { get; set; } = new(0.95f, 0.35f, 0.85f, 1f);
	[Export] public float LineWidth { get; set; } = 4f;

	private PathNetworkHost _host = null!;

	public override void _Ready()
	{
		_host = GetNode<PathNetworkHost>(NetworkHostPath);
		QueueRedraw();
	}

	public override void _Draw()
	{
		var snapshot = _host.CreateDebugSnapshot();
		foreach (var path in snapshot.Paths)
		{
			if (path.WorldPoints.Length < 2)
			{
				continue;
			}

			var points = new Vector2[path.WorldPoints.Length];
			for (var i = 0; i < path.WorldPoints.Length; i++)
			{
				points[i] = path.WorldPoints[i] - GlobalPosition;
			}

			var color = path.PathId == 0 ? PathColor : BranchColor;
			DrawPolyline(points, color, LineWidth, true);
		}

		foreach (var junction in snapshot.Junctions)
		{
			DrawCircle(junction - GlobalPosition, 9f, JunctionColor);
		}
	}
}

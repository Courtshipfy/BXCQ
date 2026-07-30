using System.Collections.Generic;
using Godot;

namespace BXCQ.PathSystem;

/// <summary>
/// Collects child Path2D Walk Paths, builds a welded PathNetwork once in _Ready.
/// Place Path2D children (or under a "WalkPaths" folder) and keep endpoints within WeldRadius.
/// </summary>
public partial class PathNetworkHost : Node2D
{
	[Export] public float WeldRadius { get; set; } = 24f;
	[Export] public float WeldSampleSpacing { get; set; } = 32f;

	private PathNetwork _network = null!;

	public override void _Ready()
	{
		Rebuild();
	}

	public void Rebuild()
	{
		var paths = new List<Path2D>();
		CollectPaths(this, paths);
		_network = PathNetwork.Build(paths, WeldRadius, WeldSampleSpacing);
		GD.Print(
			$"PathNetwork built: paths={_network.PathCount} nodes={_network.NodeCount} edges={_network.EdgeCount} weld={WeldRadius}");
	}

	internal PathNetworkMotor CreateMotor()
	{
		if (_network == null)
		{
			Rebuild();
		}
		return new PathNetworkMotor(_network);
	}

	internal PathNetworkDebugSnapshot CreateDebugSnapshot()
	{
		if (_network == null)
		{
			Rebuild();
		}
		return _network.CreateDebugSnapshot();
	}

	private static void CollectPaths(Node root, List<Path2D> paths)
	{
		foreach (var child in root.GetChildren())
		{
			if (child is Path2D path)
			{
				paths.Add(path);
			}
			else
			{
				CollectPaths(child, paths);
			}
		}
	}
}

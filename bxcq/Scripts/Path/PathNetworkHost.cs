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

	public PathNetwork Network { get; private set; } = null!;

	public override void _Ready()
	{
		Rebuild();
	}

	public void Rebuild()
	{
		var paths = new List<Path2D>();
		CollectPaths(this, paths);
		Network = PathNetwork.Build(paths, WeldRadius, WeldSampleSpacing);
		GD.Print(
			$"PathNetwork built: paths={Network.Paths.Count} nodes={Network.Nodes.Count} edges={Network.Edges.Count} weld={WeldRadius}");
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

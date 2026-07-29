using Godot;

namespace BXCQ.NarrRail;

/// <summary>Resolves a NarrRail speakerId to its world-space bubble anchor.</summary>
public static class SpeakerResolver
{
	public static Vector2 ResolveAnchor(SceneTree tree, string speakerId, Node2D fallback)
	{
		if (!string.IsNullOrWhiteSpace(speakerId))
		{
			foreach (var node in tree.GetNodesInGroup("speakers"))
			{
				if (node is ISpeakerAnchor anchor &&
					anchor.SpeakerId == speakerId)
				{
					return anchor.AnchorGlobalPosition;
				}
			}

			foreach (var node in tree.GetNodesInGroup("speakers"))
			{
				if (node is Node2D n2 && n2.Name == speakerId)
				{
					return n2.GlobalPosition;
				}
			}

			// Name fallback outside group
			var byName = FindNode2DByName(tree.Root, speakerId);
			if (byName != null)
			{
				return byName.GlobalPosition;
			}
		}

		GD.PushWarning($"SpeakerResolver: no anchor for '{speakerId}', falling back");
		if (fallback != null)
		{
			return fallback.GlobalPosition + new Vector2(0, -56);
		}

		return new Vector2(960, 200);
	}

	private static Node2D FindNode2DByName(Node root, string name)
	{
		if (root is Node2D n2 && root.Name == name)
		{
			return n2;
		}

		foreach (var child in root.GetChildren())
		{
			var found = FindNode2DByName(child, name);
			if (found != null)
			{
				return found;
			}
		}

		return null!;
	}
}

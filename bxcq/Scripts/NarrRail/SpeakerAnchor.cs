using Godot;

namespace BXCQ.NarrRail;

/// <summary>Marker / helper node that registers a SpeakerId into group speakers.</summary>
public partial class SpeakerAnchor : Marker2D, ISpeakerAnchor
{
	[Export] public string SpeakerId { get; set; } = "";
	[Export] public Vector2 BubbleOffset { get; set; } = new(0, -48);

	public Vector2 AnchorGlobalPosition => GlobalPosition + BubbleOffset;

	public override void _Ready()
	{
		if (!string.IsNullOrWhiteSpace(SpeakerId))
		{
			AddToGroup("speakers");
		}
	}
}

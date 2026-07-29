using Godot;

namespace BXCQ.NarrRail;

/// <summary>
/// World anchor for Speech Bubble. Interactables and Marker2Ds may both carry this.
/// </summary>
public interface ISpeakerAnchor
{
	string SpeakerId { get; }
	Vector2 AnchorGlobalPosition { get; }
}

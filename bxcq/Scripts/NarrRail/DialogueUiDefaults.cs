using Godot;

namespace BXCQ.NarrRail;

/// <summary>
/// Swappable presentation defaults for the placeholder dialogue UI.
/// </summary>
[GlobalClass]
public partial class DialogueUiDefaults : Resource
{
	[Export] public Font DialogueFont { get; set; }
	[Export] public float CharsPerSecond { get; set; } = 28f;
}

using Godot;
using Godot.Collections;

namespace BXCQ;

/// <summary>
/// Runtime-only world state. Narrative variables remain owned by NarrRailBridge.
/// </summary>
public partial class GameState : Node
{
	public const string VillageScenePath = "res://Scenes/DevPrototype/Locations/Village.tscn";
	public const string ChurchScenePath = "res://Scenes/DevPrototype/Locations/Church.tscn";
	public const string StudyScenePath = "res://Scenes/DevPrototype/Locations/Study.tscn";

	public string CurrentScenePath { get; set; } = VillageScenePath;
	public string PendingSpawnId { get; set; } = "default";
	public string CurrentZoneName { get; set; } = "Center";
	public bool IsDialogueBlocking { get; set; }

	private readonly Dictionary _hotspotEnabled = new();

	public string ConsumePendingSpawnId()
	{
		var spawnId = string.IsNullOrEmpty(PendingSpawnId) ? "default" : PendingSpawnId;
		PendingSpawnId = "default";
		return spawnId;
	}

	public void SetHotspotEnabled(string hotspotId, bool enabled)
	{
		if (!string.IsNullOrWhiteSpace(hotspotId))
		{
			_hotspotEnabled[hotspotId] = enabled;
		}
	}

	public bool HasHotspotOverride(string hotspotId) =>
		!string.IsNullOrWhiteSpace(hotspotId) && _hotspotEnabled.ContainsKey(hotspotId);

	public bool IsHotspotEnabled(string hotspotId, bool fallback = true) =>
		HasHotspotOverride(hotspotId) ? _hotspotEnabled[hotspotId].AsBool() : fallback;

	public void ClearRuntimeState()
	{
		CurrentScenePath = VillageScenePath;
		PendingSpawnId = "default";
		CurrentZoneName = "Center";
		IsDialogueBlocking = false;
		_hotspotEnabled.Clear();
	}

	public void CaptureWorldFromTree(SceneTree tree)
	{
		if (tree?.CurrentScene != null && !string.IsNullOrEmpty(tree.CurrentScene.SceneFilePath))
		{
			CurrentScenePath = tree.CurrentScene.SceneFilePath;
		}

		if (tree?.GetFirstNodeInGroup("camera_director") is CameraSystem.CameraDirector director)
		{
			CurrentZoneName = director.CurrentZoneName;
		}
	}
}

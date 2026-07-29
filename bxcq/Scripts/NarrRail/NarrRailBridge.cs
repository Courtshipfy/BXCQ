using Godot;
using Godot.Collections;
using BXCQ.CameraSystem;
using BXCQ.Interaction;

namespace BXCQ.NarrRail;

/// <summary>
/// Routes NarrRail world events and caches story variables across scene changes.
/// </summary>
public partial class NarrRailBridge : Node
{
	public const string EventSwitchCameraZone = "switch_camera_zone";
	public const string EventChangeScene = "change_scene";
	public const string EventSetHotspotEnabled = "set_hotspot_enabled";
	public const string VarHasClueManuscript = "has_clue_manuscript";
	public const string VarFoundManuscript = "found_manuscript";
	public const string VarHasChurchRelicClue = "has_church_relic_clue";

	private GodotObject _router = null!;
	private GodotObject _activeSession = null!;
	private readonly Dictionary _storyVariables = new();

	public override void _Ready()
	{
		var routerScript = GD.Load<GDScript>("res://addons/narrrail/runtime/narrrail_event_router.gd");
		if (routerScript == null)
		{
			GD.PushError("NarrRailBridge: narrrail_event_router.gd missing");
			return;
		}

		_router = (GodotObject)routerScript.New();
		_router.Call("register_type", EventSwitchCameraZone, Callable.From((Dictionary payload) => OnSwitchCameraZone(payload)));
		_router.Call("register_type", EventChangeScene, Callable.From((Dictionary payload) => OnChangeScene(payload)));
		_router.Call("register_type", EventSetHotspotEnabled, Callable.From((Dictionary payload) => OnSetHotspotEnabled(payload)));
		GD.Print("NarrRailBridge ready");
	}

	/// <returns>true if a world handler consumed the eventType.</returns>
	public bool TryHandle(Dictionary payload, GodotObject session)
	{
		_activeSession = session;
		return _router.Call("dispatch", payload).AsBool();
	}

	public void ClearSession(GodotObject session)
	{
		if (_activeSession == session)
		{
			_activeSession = null!;
		}
	}

	/// <summary>Snapshot injected into session.start as initial_variables.</summary>
	public Dictionary CreateInitialVariables() => _storyVariables.Duplicate(true);

	public void MergeVariableSnapshot(Dictionary snapshot)
	{
		foreach (var key in snapshot.Keys)
		{
			_storyVariables[key] = snapshot[key];
		}
	}

	public void OnVariableChanged(Dictionary payload)
	{
		if (!payload.ContainsKey("name"))
		{
			return;
		}

		var name = payload["name"].AsString();
		if (string.IsNullOrEmpty(name) || !payload.ContainsKey("newValue"))
		{
			return;
		}

		_storyVariables[name] = payload["newValue"];
		GD.Print($"Story variable: {name}={payload["newValue"]}");
	}

	public bool GetBool(string name, bool fallback = false)
	{
		if (!_storyVariables.ContainsKey(name))
		{
			return fallback;
		}

		return _storyVariables[name].AsBool();
	}

	public void SetBool(string name, bool value)
	{
		_storyVariables[name] = value;
	}

	public bool HasVariable(string name) => _storyVariables.ContainsKey(name);

	/// <summary>Clears cached story variables (New Game).</summary>
	public void ClearStoryVariables()
	{
		_storyVariables.Clear();
		_activeSession = null!;
		GD.Print("NarrRailBridge: story variables cleared");
	}

	private void OnSwitchCameraZone(Dictionary payload)
	{
		var zoneName = ReadParamString(payload, "zoneName");
		if (string.IsNullOrWhiteSpace(zoneName))
		{
			GD.PushWarning("NarrRailBridge: switch_camera_zone missing params.zoneName");
			return;
		}

		var director = FindCameraDirector();
		if (director == null)
		{
			GD.PushWarning("NarrRailBridge: CameraDirector not found");
			return;
		}

		if (!director.TryRequestZoneByName(zoneName))
		{
			GD.PushWarning($"NarrRailBridge: camera zone '{zoneName}' not found");
			return;
		}

		var gameState = GetNodeOrNull<GameState>("/root/GameState");
		if (gameState != null)
		{
			gameState.CurrentZoneName = zoneName;
		}

		GD.Print($"NarrRail bridge: switch_camera_zone -> {zoneName}");
	}

	private void OnChangeScene(Dictionary payload)
	{
		var scenePath = ReadParamString(payload, "scenePath");
		if (string.IsNullOrWhiteSpace(scenePath))
		{
			GD.PushWarning("NarrRailBridge: change_scene missing params.scenePath");
			return;
		}

		var spawnId = ReadParamString(payload, "spawnId");
		if (string.IsNullOrWhiteSpace(spawnId))
		{
			spawnId = "default";
		}

		var gameState = GetNodeOrNull<GameState>("/root/GameState");
		if (gameState != null)
		{
			gameState.IsDialogueBlocking = false;
			gameState.CaptureWorldFromTree(GetTree());
		}

		GD.Print($"NarrRail bridge: change_scene -> {scenePath} spawn={spawnId}");
		GetNode<SceneTransition>("/root/SceneTransition").GoTo(scenePath, spawnId);
	}

	private void OnSetHotspotEnabled(Dictionary payload)
	{
		var hotspotId = ReadParamString(payload, "hotspotId");
		if (string.IsNullOrWhiteSpace(hotspotId))
		{
			GD.PushWarning("NarrRailBridge: set_hotspot_enabled missing params.hotspotId");
			return;
		}

		var enabled = true;
		if (payload.ContainsKey("params") && payload["params"].VariantType == Variant.Type.Dictionary)
		{
			var parameters = payload["params"].AsGodotDictionary();
			if (parameters.ContainsKey("enabled"))
			{
				enabled = parameters["enabled"].AsBool();
			}
		}

		GetNodeOrNull<GameState>("/root/GameState")?.SetHotspotEnabled(hotspotId, enabled);

		SceneHotspot match = null!;
		foreach (var node in GetTree().GetNodesInGroup("scene_hotspots"))
		{
			if (node is SceneHotspot hotspot && hotspot.MatchesHotspotId(hotspotId))
			{
				match = hotspot;
				break;
			}
		}

		if (match == null)
		{
			GD.PushWarning($"NarrRailBridge: hotspot '{hotspotId}' not found");
			return;
		}

		match.IsEnabled = enabled;
		GD.Print($"NarrRail bridge: set_hotspot_enabled {hotspotId}={enabled}");
	}

	private static string ReadParamString(Dictionary payload, string key)
	{
		if (!payload.ContainsKey("params") || payload["params"].VariantType != Variant.Type.Dictionary)
		{
			return "";
		}

		var parameters = payload["params"].AsGodotDictionary();
		return parameters.ContainsKey(key) ? parameters[key].AsString() : "";
	}

	private CameraDirector FindCameraDirector()
	{
		var scene = GetTree().CurrentScene;
		return scene?.GetNodeOrNull<CameraDirector>("CameraDirector")
			?? GetTree().GetFirstNodeInGroup("camera_director") as CameraDirector;
	}
}

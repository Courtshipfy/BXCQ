using System;
using System.Collections.Generic;
using Godot;
using Godot.Collections;

namespace BXCQ.NarrRail;

/// <summary>
/// Owns NarrRail story loading, Session lifecycle, event dispatch, variable snapshots,
/// and Dialogue Blocking. Presentation adapters subscribe to its observable outcomes.
/// </summary>
public partial class NarrRailExecution : Node
{
	private const string SessionScriptPath = "res://addons/narrrail/runtime/narrrail_session.gd";
	private const string StoryLoaderPath = "res://addons/narrrail/runtime/story_resource_loader.gd";

	private GodotObject _session = null!;
	private GDScript _storyLoader = null!;
	private GameState _gameState = null!;
	private NarrRailBridge _bridge = null!;
	private PresentationDirector _presentation = null!;
	private bool _startFailed;

	public event Action StoryStarted;
	public event Action<string, string> LineChanged;
	public event Action<string[]> ChoicesChanged;
	public event Action StoryEnded;
	public event Action<string> StoryFailed;

	public bool IsRunning { get; private set; }
	public bool IsWaitingForChoice => ReadSessionState() == "waiting_choice";
	public bool IsPaused => ReadSessionState() == "paused";
	public string LastLineText { get; private set; } = "";

	public override void _Ready()
	{
		_gameState = GetNode<GameState>("/root/GameState");
		_bridge = GetNode<NarrRailBridge>("/root/NarrRailBridge");
		_presentation = GetNode<PresentationDirector>("/root/PresentationDirector");
		_storyLoader = GD.Load<GDScript>(StoryLoaderPath);

		var sessionScript = GD.Load<GDScript>(SessionScriptPath);
		if (_storyLoader == null || sessionScript == null)
		{
			GD.PushError("NarrRailExecution: NarrRail runtime scripts are missing");
			return;
		}

		_session = (GodotObject)sessionScript.New();
		_session.Connect("line_changed", Callable.From((Dictionary payload) => OnLineChanged(payload)));
		_session.Connect("choices_changed", Callable.From((Godot.Collections.Array choices) => OnChoicesChanged(choices)));
		_session.Connect("event_emitted", Callable.From((Dictionary payload) => OnEventEmitted(payload)));
		_session.Connect("variable_changed", Callable.From((Dictionary payload) => _bridge.OnVariableChanged(payload)));
		_session.Connect("ended", Callable.From(OnEnded));
		_session.Connect("error_raised", Callable.From((string message) => OnError(message)));
		GD.Print("NarrRailExecution ready");
	}

	public bool StartStory(string storyPath)
	{
		if (_session == null || _storyLoader == null || IsRunning || _gameState.IsDialogueBlocking)
		{
			return false;
		}

		var resultVariant = _storyLoader.Call("load_story", storyPath);
		if (resultVariant.VariantType != Variant.Type.Dictionary)
		{
			return false;
		}

		var result = resultVariant.AsGodotDictionary();
		if (!(result.ContainsKey("ok") && (bool)result["ok"]))
		{
			var error = result.ContainsKey("error") ? result["error"].AsString() : "unknown";
			GD.PushError($"NarrRail load failed: {error}");
			return false;
		}

		LastLineText = "";
		_startFailed = false;
		IsRunning = true;
		_gameState.IsDialogueBlocking = true;
		StoryStarted?.Invoke();
		_session.Call("start", result["story"].AsGodotDictionary(), _bridge.CreateInitialVariables());
		GD.Print($"NarrRailExecution started {storyPath}");
		return !_startFailed;
	}

	public bool Advance()
	{
		if (!IsRunning || IsPaused || IsWaitingForChoice)
		{
			return false;
		}

		_session.Call("next");
		return true;
	}

	public bool Choose(int index)
	{
		if (!IsRunning || IsPaused || !IsWaitingForChoice || index < 0)
		{
			return false;
		}

		_session.Call("choose", index);
		return true;
	}

	private void OnLineChanged(Dictionary payload)
	{
		var speakerId = payload.ContainsKey("speakerId") ? payload["speakerId"].AsString() : "";
		var text = payload.ContainsKey("textKey") ? payload["textKey"].AsString() : "";
		LastLineText = text;
		LineChanged?.Invoke(speakerId, text);
	}

	private void OnChoicesChanged(Godot.Collections.Array choices)
	{
		var labels = new List<string>();
		foreach (var item in choices)
		{
			if (item.VariantType != Variant.Type.Dictionary)
			{
				continue;
			}

			var choice = item.AsGodotDictionary();
			labels.Add(choice.ContainsKey("textKey") ? choice["textKey"].AsString() : "(choice)");
		}

		ChoicesChanged?.Invoke(labels.ToArray());
	}

	private void OnEventEmitted(Dictionary payload)
	{
		var handled = _presentation.TryHandle(payload, _session);
		handled |= _bridge.TryHandle(payload, _session);
		if (handled)
		{
			return;
		}

		var type = payload.ContainsKey("eventType") ? payload["eventType"].AsString() : "";
		GD.PushWarning($"NarrRailExecution: unhandled eventType '{type}'");
	}

	private void OnEnded()
	{
		Finish(mergeVariables: true);
		StoryEnded?.Invoke();
		GD.Print("NarrRailExecution: story ended");
	}

	private void OnError(string message)
	{
		_startFailed = true;
		GD.PushError($"NarrRail error: {message}");
		Finish(mergeVariables: false);
		StoryFailed?.Invoke(message);
	}

	private void Finish(bool mergeVariables)
	{
		if (mergeVariables && _session != null)
		{
			_bridge.MergeVariableSnapshot(_session.Call("get_variable_snapshot").AsGodotDictionary());
		}

		_bridge.ClearSession(_session);
		_presentation.ClearSession(_session);
		IsRunning = false;
		_gameState.IsDialogueBlocking = false;
	}

	private string ReadSessionState()
	{
		if (!IsRunning || _session == null)
		{
			return "idle";
		}

		var state = _session.Call("get_state").AsGodotDictionary();
		return state.ContainsKey("state") ? state["state"].AsString() : "idle";
	}
}

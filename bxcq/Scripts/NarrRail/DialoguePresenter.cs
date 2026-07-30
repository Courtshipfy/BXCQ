using Godot;
using Godot.Collections;
using System.Collections.Generic;

namespace BXCQ.NarrRail;

/// <summary>
/// Dialogue + Examine Presenter — NarrRail bubbles and short object Examine mode.
/// </summary>
public partial class DialoguePresenter : CanvasLayer
{
	private const string BubbleScenePath = "res://Scenes/UI/AdaptiveSpeechBubble.tscn";

	[Export] public string SampleStoryPath { get; set; } = "res://Stories/DevPrototype/village_elder_hello.nrstory";
	[Export] public DialogueUiDefaults Defaults { get; set; }

	private GodotObject _session = null!;
	private SpeechBubbleView _bubble = null!;
	private GameState _gameState = null!;
	private Node2D _player = null!;

	private bool _running;
	private bool _examining;
	private bool _waitingChoice;
	private string _fullLine = "";
	private string _speakerId = "";
	private int _visibleChars;
	private float _typeAccumulator;
	private bool _revealComplete = true;
	private Vector2 _worldAnchor;

	public bool IsRunning => _running;
	public bool IsExamining => _examining;
	public string LastLineText { get; private set; } = "";

	public override void _Ready()
	{
		Layer = 35;
		Defaults ??= GD.Load<DialogueUiDefaults>("res://Resources/Ui/DialogueUiDefaults.tres");
		_gameState = GetNode<GameState>("/root/GameState");

		var bubbleScene = GD.Load<PackedScene>(BubbleScenePath);
		if (bubbleScene == null)
		{
			GD.PushError($"DialoguePresenter: bubble scene missing at {BubbleScenePath}");
			return;
		}

		_bubble = bubbleScene.Instantiate<SpeechBubbleView>();
		_bubble.Name = "SpeechBubble";
		AddChild(_bubble);
		if (Defaults?.DialogueFont != null)
		{
			_bubble.ApplyFont(Defaults.DialogueFont);
		}

		_bubble.ChoiceSelected += OnChoicePicked;


		var sessionScript = GD.Load<GDScript>("res://addons/narrrail/runtime/narrrail_session.gd");
		if (sessionScript == null)
		{
			GD.PushError("DialoguePresenter: narrrail_session.gd missing");
			return;
		}

		_session = (GodotObject)sessionScript.New();
		_session.Connect("line_changed", Callable.From((Dictionary payload) => OnLineChanged(payload)));
		_session.Connect("choices_changed", Callable.From((Array choices) => OnChoicesChanged(choices)));
		_session.Connect("event_emitted", Callable.From((Dictionary payload) => OnEventEmitted(payload)));
		_session.Connect("variable_changed", Callable.From((Dictionary payload) => OnVariableChanged(payload)));
		_session.Connect("ended", Callable.From(OnEnded));
		_session.Connect("error_raised", Callable.From((string message) => OnError(message)));

		AddToGroup("dialogue_presenter");
		AddToGroup("narrrail_player");
		CallDeferred(nameof(CachePlayer));
		GD.Print("DialoguePresenter ready");
	}

	private void CachePlayer()
	{
		_player = GetTree().GetFirstNodeInGroup("player") as Node2D
			?? GetNodeOrNull<Node2D>("../Player");
	}

	public bool StartSampleStory() => StartStory(SampleStoryPath);

	/// <summary>Shows one-shot Examine text; click or Space dismisses it.</summary>
	public bool ShowExamine(Vector2 worldAnchor, string title, string body)
	{
		if (_running || _examining || string.IsNullOrWhiteSpace(body))
		{
			return false;
		}

		_examining = true;
		_waitingChoice = false;
		_revealComplete = true;
		_speakerId = title ?? "";
		_fullLine = body;
		LastLineText = body;
		_worldAnchor = worldAnchor;
		_bubble.ClearChoices();
		_bubble.BeginLine(_speakerId, _fullLine);
		_bubble.SetVisibleText(_fullLine);
		_gameState.IsDialogueBlocking = true;
		UpdateBubblePlacement();
		GD.Print($"Examine: [{_speakerId}] {_fullLine}");
		return true;
	}

	public void DismissExamine()
	{
		if (!_examining)
		{
			return;
		}

		_examining = false;
		_bubble.HideBubble();
		_gameState.IsDialogueBlocking = false;
		GD.Print("Examine dismissed");
	}

	public bool StartStory(string storyPath)
	{
		if (_session == null || _running || _examining)
		{
			return false;
		}

		var loader = GD.Load<GDScript>("res://addons/narrrail/runtime/story_resource_loader.gd");
		var resultVariant = loader.Call("load_story", storyPath);
		if (resultVariant.VariantType != Variant.Type.Dictionary)
		{
			return false;
		}

		var result = resultVariant.AsGodotDictionary();
		if (!(result.ContainsKey("ok") && (bool)result["ok"]))
		{
			var err = result.ContainsKey("error") ? result["error"].AsString() : "unknown";
			GD.PushError($"NarrRail load failed: {err}");
			return false;
		}

		_waitingChoice = false;
		_bubble.ClearChoices();
		var bridge = GetNodeOrNull<NarrRailBridge>("/root/NarrRailBridge");
		var initialVars = bridge?.CreateInitialVariables() ?? new Dictionary();
		_session.Call("start", result["story"].AsGodotDictionary(), initialVars);
		_running = true;
		_gameState.IsDialogueBlocking = true;
		GD.Print($"DialoguePresenter started {storyPath}");
		return true;
	}

	public override void _Process(double delta)
	{
		if (_examining)
		{
			UpdateBubblePlacement();
			return;
		}

		if (!_running)
		{
			return;
		}

		UpdateBubblePlacement();

		if (_revealComplete || _waitingChoice)
		{
			return;
		}

		var cps = Defaults?.CharsPerSecond > 0 ? Defaults.CharsPerSecond : 28f;
		_typeAccumulator += (float)delta * cps;
		var add = (int)_typeAccumulator;
		if (add <= 0)
		{
			return;
		}

		_typeAccumulator -= add;
		var next = Mathf.Min(_fullLine.Length, _visibleChars + add);
		if (next != _visibleChars)
		{
			_visibleChars = next;
			_bubble.SetVisibleText(_fullLine[.._visibleChars]);
		}

		if (_visibleChars >= _fullLine.Length)
		{
			_revealComplete = true;
		}
	}

	public override void _UnhandledInput(InputEvent @event)
	{
		var advance = @event.IsActionPressed("ui_accept") ||
			@event is InputEventMouseButton { Pressed: true, ButtonIndex: MouseButton.Left };
		if (!advance)
		{
			return;
		}

		if (_examining)
		{
			DismissExamine();
			GetViewport().SetInputAsHandled();
			return;
		}

		if (!_running || _waitingChoice)
		{
			return;
		}

		if (!_revealComplete)
		{
			_visibleChars = _fullLine.Length;
			_revealComplete = true;
			_bubble.SetVisibleText(_fullLine);
			GetViewport().SetInputAsHandled();
			return;
		}

		_session.Call("next");
		GetViewport().SetInputAsHandled();
	}

	private void OnLineChanged(Dictionary payload)
	{
		_waitingChoice = false;
		_speakerId = payload.ContainsKey("speakerId") ? payload["speakerId"].AsString() : "";
		_fullLine = payload.ContainsKey("textKey") ? payload["textKey"].AsString() : "";
		LastLineText = _fullLine;
		_visibleChars = 0;
		_typeAccumulator = 0f;
		_revealComplete = string.IsNullOrEmpty(_fullLine);
		_worldAnchor = SpeakerResolver.ResolveAnchor(GetTree(), _speakerId, _player);
		_bubble.BeginLine(_speakerId, _fullLine);
		UpdateBubblePlacement();
		GD.Print($"Dialogue line: [{_speakerId}] {_fullLine}");
	}

	private void OnChoicesChanged(Array choices)
	{
		_waitingChoice = true;
		_revealComplete = true;
		var labels = new List<string>();
		foreach (var item in choices)
		{
			if (item.VariantType != Variant.Type.Dictionary)
			{
				continue;
			}

			var dict = item.AsGodotDictionary();
			var text = dict.ContainsKey("textKey") ? dict["textKey"].AsString() : "(choice)";
			labels.Add(text);
		}

		_bubble.ShowChoices(labels.ToArray());
		UpdateBubblePlacement();
		GD.Print($"Dialogue choices: {labels.Count}");
	}

	private void OnChoicePicked(int index)
	{
		if (!_waitingChoice)
		{
			return;
		}

		_waitingChoice = false;
		_bubble.ClearChoices();
		_session.Call("choose", index);
	}

	private void OnEventEmitted(Dictionary payload)
	{
		var presentation = GetNodeOrNull<PresentationDirector>("/root/PresentationDirector");
		var bridge = GetNodeOrNull<NarrRailBridge>("/root/NarrRailBridge");

		var handled = false;
		if (presentation != null)
		{
			handled |= presentation.TryHandle(payload, _session);
		}

		if (bridge != null)
		{
			handled |= bridge.TryHandle(payload, _session);
		}

		if (!handled)
		{
			var type = payload.ContainsKey("eventType") ? payload["eventType"].AsString() : "";
			GD.PushWarning($"DialoguePresenter: unhandled eventType '{type}'");
		}
	}

	private void OnVariableChanged(Dictionary payload)
	{
		GetNodeOrNull<NarrRailBridge>("/root/NarrRailBridge")?.OnVariableChanged(payload);
	}

	private void OnEnded()
	{
		_running = false;
		_waitingChoice = false;
		_gameState.IsDialogueBlocking = false;
		_revealComplete = true;
		_bubble.HideBubble();
		var bridge = GetNodeOrNull<NarrRailBridge>("/root/NarrRailBridge");
		if (bridge != null && _session != null)
		{
			var snapshot = _session.Call("get_variable_snapshot").AsGodotDictionary();
			bridge.MergeVariableSnapshot(snapshot);
			bridge.ClearSession(_session);
		}

		GetNodeOrNull<PresentationDirector>("/root/PresentationDirector")?.ClearSession(_session);
		GD.Print("DialoguePresenter: story ended");
	}

	private void OnError(string message)
	{
		GD.PushError($"NarrRail error: {message}");
		_running = false;
		_waitingChoice = false;
		_gameState.IsDialogueBlocking = false;
		_bubble.HideBubble();
		GetNodeOrNull<NarrRailBridge>("/root/NarrRailBridge")?.ClearSession(_session);
		GetNodeOrNull<PresentationDirector>("/root/PresentationDirector")?.ClearSession(_session);
	}

	/// <summary>Headless/smoke helper: skip typing or advance / pick first choice.</summary>
	public void SmokeAdvance()
	{
		if (!_running || _session == null)
		{
			return;
		}

		var state = _session.Call("get_state").AsGodotDictionary();
		var sessionState = state.ContainsKey("state") ? state["state"].AsString() : "";
		if (sessionState == "paused")
		{
			return;
		}

		if (!_revealComplete)
		{
			_visibleChars = _fullLine.Length;
			_revealComplete = true;
			_bubble.SetVisibleText(_fullLine);
			return;
		}

		if (_waitingChoice)
		{
			OnChoicePicked(0);
			return;
		}

		_session.Call("next");
	}

	private void UpdateBubblePlacement()
	{
		if (!_bubble.Visible)
		{
			return;
		}

		if (_running && !_examining)
		{
			_worldAnchor = SpeakerResolver.ResolveAnchor(GetTree(), _speakerId, _player);
		}

		var canvas = GetViewport().GetCanvasTransform();
		var screen = canvas * _worldAnchor;
		_bubble.PlaceAtScreenAnchor(screen, GetViewport().GetVisibleRect().Size);
	}

}

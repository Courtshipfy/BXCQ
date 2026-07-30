using Godot;

namespace BXCQ.NarrRail;

/// <summary>Renders NarrRail lines and choices plus one-shot Examine text.</summary>
public partial class DialoguePresenter : CanvasLayer
{
	private const string BubbleScenePath = "res://Scenes/UI/AdaptiveSpeechBubble.tscn";

	[Export] public DialogueUiDefaults Defaults { get; set; }

	private NarrRailExecution _execution = null!;
	private SpeechBubbleView _bubble = null!;
	private GameState _gameState = null!;
	private Node2D _player = null!;

	private bool _examining;
	private bool _waitingChoice;
	private string _fullLine = "";
	private string _speakerId = "";
	private int _visibleChars;
	private float _typeAccumulator;
	private bool _revealComplete = true;
	private Vector2 _worldAnchor;

	public bool IsExamining => _examining;
	public string LastLineText { get; private set; } = "";

	public override void _Ready()
	{
		Layer = 35;
		Defaults ??= GD.Load<DialogueUiDefaults>("res://Resources/Ui/DialogueUiDefaults.tres");
		_gameState = GetNode<GameState>("/root/GameState");
		_execution = GetNode<NarrRailExecution>("/root/NarrRailExecution");

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
		_execution.StoryStarted += OnStoryStarted;
		_execution.LineChanged += OnLineChanged;
		_execution.ChoicesChanged += OnChoicesChanged;
		_execution.StoryEnded += OnStoryEnded;
		_execution.StoryFailed += OnStoryFailed;
		AddToGroup("dialogue_presenter");
		CallDeferred(nameof(CachePlayer));
		GD.Print("DialoguePresenter ready");
	}

	public override void _ExitTree()
	{
		if (_execution != null)
		{
			_execution.StoryStarted -= OnStoryStarted;
			_execution.LineChanged -= OnLineChanged;
			_execution.ChoicesChanged -= OnChoicesChanged;
			_execution.StoryEnded -= OnStoryEnded;
			_execution.StoryFailed -= OnStoryFailed;
		}
	}

	private void CachePlayer()
	{
		_player = GetTree().GetFirstNodeInGroup("player") as Node2D
			?? GetNodeOrNull<Node2D>("../Player");
	}

	/// <summary>Shows one-shot Examine text; click or Space dismisses it.</summary>
	public bool ShowExamine(Vector2 worldAnchor, string title, string body)
	{
		if (_execution.IsRunning || _examining || string.IsNullOrWhiteSpace(body))
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

	public override void _Process(double delta)
	{
		if (_examining)
		{
			UpdateBubblePlacement();
			return;
		}

		if (!_execution.IsRunning)
		{
			return;
		}

		UpdateBubblePlacement();
		if (_revealComplete || _waitingChoice)
		{
			return;
		}

		var charsPerSecond = Defaults?.CharsPerSecond > 0 ? Defaults.CharsPerSecond : 28f;
		_typeAccumulator += (float)delta * charsPerSecond;
		var addedChars = (int)_typeAccumulator;
		if (addedChars <= 0)
		{
			return;
		}

		_typeAccumulator -= addedChars;
		var next = Mathf.Min(_fullLine.Length, _visibleChars + addedChars);
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

		if (!_execution.IsRunning || _waitingChoice || _execution.IsPaused)
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

		_execution.Advance();
		GetViewport().SetInputAsHandled();
	}

	private void OnStoryStarted()
	{
		_waitingChoice = false;
		_revealComplete = true;
		_bubble.ClearChoices();
	}

	private void OnLineChanged(string speakerId, string text)
	{
		_waitingChoice = false;
		_speakerId = speakerId;
		_fullLine = text;
		LastLineText = text;
		_visibleChars = 0;
		_typeAccumulator = 0f;
		_revealComplete = string.IsNullOrEmpty(_fullLine);
		_worldAnchor = SpeakerResolver.ResolveAnchor(GetTree(), _speakerId, _player);
		_bubble.BeginLine(_speakerId, _fullLine);
		UpdateBubblePlacement();
		GD.Print($"Dialogue line: [{_speakerId}] {_fullLine}");
	}

	private void OnChoicesChanged(string[] labels)
	{
		_waitingChoice = true;
		_revealComplete = true;
		_bubble.ShowChoices(labels);
		UpdateBubblePlacement();
		GD.Print($"Dialogue choices: {labels.Length}");
	}

	private void OnChoicePicked(int index)
	{
		if (!_waitingChoice || !_execution.Choose(index))
		{
			return;
		}

		_waitingChoice = false;
		_bubble.ClearChoices();
	}

	private void OnStoryEnded()
	{
		_waitingChoice = false;
		_revealComplete = true;
		_bubble.HideBubble();
	}

	private void OnStoryFailed(string message)
	{
		_waitingChoice = false;
		_revealComplete = true;
		_bubble.HideBubble();
	}

	private void UpdateBubblePlacement()
	{
		if (!_bubble.Visible)
		{
			return;
		}

		if (_execution.IsRunning && !_examining)
		{
			_worldAnchor = SpeakerResolver.ResolveAnchor(GetTree(), _speakerId, _player);
		}

		var canvas = GetViewport().GetCanvasTransform();
		var screen = canvas * _worldAnchor;
		_bubble.PlaceAtScreenAnchor(screen, GetViewport().GetVisibleRect().Size);
	}
}

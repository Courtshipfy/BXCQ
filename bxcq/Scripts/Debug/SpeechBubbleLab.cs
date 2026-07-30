using BXCQ.NarrRail;
using Godot;
using System;

namespace BXCQ.DebugTools;

/// <summary>
/// Standalone visual harness for exercising the production speech bubble with
/// different content volumes and screen anchors.
/// </summary>
public partial class SpeechBubbleLab : Control
{
	private const float DemoCharsPerSecond = 32f;

	private sealed class DemoLine
	{
		public DemoLine(string speaker, int sampleIndex, int positionIndex, bool hasChoices = false)
		{
			Speaker = speaker;
			SampleIndex = sampleIndex;
			PositionIndex = positionIndex;
			HasChoices = hasChoices;
		}

		public string Speaker { get; }
		public int SampleIndex { get; }
		public int PositionIndex { get; }
		public bool HasChoices { get; }
	}

	private static readonly string[] SampleNames =
	[
		"短句",
		"单行",
		"中等",
		"长文",
		"超长",
	];

	private static readonly string[] SampleTexts =
	[
		"好。",
		"风从旧城墙上掠过，远处传来暮鼓。",
		"案上的竹简少了一册，墨迹却还是新的。若现在沿着廊下追过去，也许还能找到留下脚印的人。",
		"我把散落的残页重新排了一遍，才发现每一页边角都有极淡的朱砂记号。它们并不是页码，而是一条被拆开的路线：从村口的古井开始，穿过祠堂后墙，最后指向山腰那座多年无人看守的旧亭。",
		"雨下了一整夜。天亮时，院里的石阶被冲洗得发白，只有门槛内侧还留着半枚泥印。那人显然在这里停过，却没有进屋。\n\n我又检查了灯台、窗栓和书案。灯油比昨晚少了一截，窗纸没有破，锁也完好。真正奇怪的是砚台：墨已经干了，砚底却压着一根新折的芦苇。若把它与河滩捡到的那束芦花放在一起，或许能说明来人从哪里绕进了城。",
	];

	private static readonly string[] PositionNames =
	[
		"左上", "上中", "右上",
		"左中", "中心", "右中",
		"左下", "下中", "右下",
	];

	private static readonly Vector2[] PositionRatios =
	[
		new(0.08f, 0.12f), new(0.50f, 0.12f), new(0.92f, 0.12f),
		new(0.08f, 0.52f), new(0.50f, 0.52f), new(0.92f, 0.52f),
		new(0.08f, 0.90f), new(0.50f, 0.90f), new(0.92f, 0.90f),
	];

	private readonly string[] _choiceSamples =
	[
		"追问他昨夜看见了什么",
		"检查桌上的残卷、墨迹与封蜡",
		"暂且离开，之后再回来",
	];

	private readonly DemoLine[] _demoLines =
	[
		new("井边老者", 0, 6),
		new("旅人", 1, 8),
		new("史官", 2, 4),
		new("守亭人", 3, 3),
		new("抄书吏", 4, 5, hasChoices: true),
	];

	private SpeechBubbleView _bubble = null!;
	private Control _stage = null!;
	private Control _anchorMarker = null!;
	private Control _bubbleBounds = null!;
	private TextEdit _textEditor = null!;
	private LineEdit _speakerEditor = null!;
	private CheckButton _speakerToggle = null!;
	private CheckButton _choicesToggle = null!;
	private Label _scenarioLabel = null!;
	private Label _diagnosticsLabel = null!;
	private Vector2 _anchorLocal;
	private int _sampleIndex = 2;
	private int _positionIndex = 4;
	private bool _usingCustomAnchor;
	private bool _demoMode;
	private bool _revealComplete;
	private bool _waitingForChoice;
	private int _demoIndex;
	private int _visibleCharacters;
	private float _typeAccumulator;
	private string _currentFullText = "";

	public override void _Ready()
	{
		_bubble = GetNode<SpeechBubbleView>("Stage/AdaptiveSpeechBubble");
		_stage = GetNode<Control>("Stage");
		_anchorMarker = GetNode<Control>("Stage/AnchorMarker");
		_bubbleBounds = GetNode<Control>("Stage/BubbleBounds");
		ConfigureBubbleMousePassThrough(_bubble);
		_textEditor = GetNode<TextEdit>("Sidebar/Margin/Scroll/Controls/CustomText");
		_speakerEditor = GetNode<LineEdit>("Sidebar/Margin/Scroll/Controls/SpeakerRow/SpeakerName");
		_speakerToggle = GetNode<CheckButton>("Sidebar/Margin/Scroll/Controls/SpeakerRow/ShowSpeaker");
		_choicesToggle = GetNode<CheckButton>("Sidebar/Margin/Scroll/Controls/ShowChoices");
		_scenarioLabel = GetNode<Label>("Sidebar/Margin/Scroll/Controls/Scenario");
		_diagnosticsLabel = GetNode<Label>("Sidebar/Margin/Scroll/Controls/Diagnostics");

		for (var i = 0; i < SampleTexts.Length; i++)
		{
			var index = i;
			GetNode<Button>($"Sidebar/Margin/Scroll/Controls/TextPresets/Text{index}").Pressed +=
				() => SelectTextSample(index);
		}

		for (var i = 0; i < PositionRatios.Length; i++)
		{
			var index = i;
			GetNode<Button>($"Sidebar/Margin/Scroll/Controls/PositionPresets/Position{index}").Pressed +=
				() => SelectPosition(index);
		}

		GetNode<Button>("Sidebar/Margin/Scroll/Controls/ApplyText").Pressed += ApplyCurrentContent;
		GetNode<Button>("Sidebar/Margin/Scroll/Controls/PlayDemo").Pressed += StartDemo;
		GetNode<Button>("Sidebar/Margin/Scroll/Controls/Reset").Pressed += ResetLab;
		_speakerToggle.Toggled += _ => ApplyCurrentContent();
		_choicesToggle.Toggled += _ => ApplyCurrentContent();
		_speakerEditor.TextSubmitted += _ => ApplyCurrentContent();
		_stage.GuiInput += OnStageGuiInput;
		_stage.Resized += PlaceAtSelectedAnchor;
		_bubble.ChoiceSelected += OnDemoChoiceSelected;

		_textEditor.Text = SampleTexts[_sampleIndex];
		CallDeferred(nameof(InitializeLab));
	}

	public override void _Process(double delta)
	{
		UpdateDemoTypewriter((float)delta);
		PlaceBubble();
		UpdateVisualDiagnostics();
	}

	private void InitializeLab()
	{
		StartDemo();
	}

	private void SelectTextSample(int index)
	{
		_demoMode = false;
		_sampleIndex = Mathf.Clamp(index, 0, SampleTexts.Length - 1);
		_textEditor.Text = SampleTexts[_sampleIndex];
		ApplyCurrentContent();
	}

	private void SelectPosition(int index)
	{
		_positionIndex = Mathf.Clamp(index, 0, PositionRatios.Length - 1);
		_usingCustomAnchor = false;
		PlaceAtSelectedAnchor();
	}

	private void ResetLab()
	{
		StartDemo();
	}

	private void ApplyCurrentContent()
	{
		_demoMode = false;
		_waitingForChoice = false;
		_revealComplete = true;
		var speaker = _speakerToggle.ButtonPressed ? _speakerEditor.Text : "";
		var text = _textEditor.Text ?? "";
		_bubble.BeginLine(speaker, text);
		_bubble.SetVisibleText(text);
		if (_choicesToggle.ButtonPressed)
		{
			_bubble.ShowChoices(_choiceSamples);
		}
		else
		{
			_bubble.ClearChoices();
		}
		PlaceBubble();
	}

	private void PlaceAtSelectedAnchor()
	{
		if (!_usingCustomAnchor)
		{
			var ratio = PositionRatios[_positionIndex];
			_anchorLocal = new Vector2(_stage.Size.X * ratio.X, _stage.Size.Y * ratio.Y);
		}
		else
		{
			_anchorLocal = new Vector2(
				Mathf.Clamp(_anchorLocal.X, 0f, _stage.Size.X),
				Mathf.Clamp(_anchorLocal.Y, 0f, _stage.Size.Y));
		}
		PlaceBubble();
	}

	private void PlaceBubble()
	{
		if (_bubble == null || _stage == null)
		{
			return;
		}

		_anchorMarker.Position = _anchorLocal - _anchorMarker.Size * 0.5f;
		_bubble.PlaceAtScreenAnchorInRect(
			_stage.GlobalPosition + _anchorLocal,
			new Rect2(_stage.GlobalPosition, _stage.Size));
	}

	private void OnStageGuiInput(InputEvent inputEvent)
	{
		if (inputEvent is not InputEventMouseButton
			{
				Pressed: true,
			} mouse)
		{
			return;
		}

		if (mouse.ButtonIndex == MouseButton.Right)
		{
			_usingCustomAnchor = true;
			_anchorLocal = mouse.Position;
			PlaceBubble();
		}
		else if (mouse.ButtonIndex == MouseButton.Left)
		{
			AdvanceDemoByClick();
		}
		else
		{
			return;
		}
		AcceptEvent();
	}

	private void StartDemo()
	{
		_demoMode = true;
		_demoIndex = 0;
		ShowDemoLine();
	}

	private void ShowDemoLine()
	{
		var line = _demoLines[_demoIndex];
		_sampleIndex = line.SampleIndex;
		_positionIndex = line.PositionIndex;
		_usingCustomAnchor = false;
		_currentFullText = SampleTexts[_sampleIndex];
		_visibleCharacters = 0;
		_typeAccumulator = 0f;
		_revealComplete = string.IsNullOrEmpty(_currentFullText);
		_waitingForChoice = line.HasChoices;
		_textEditor.Text = _currentFullText;
		_speakerEditor.Text = line.Speaker;
		_bubble.BeginLine(line.Speaker, _currentFullText);
		_bubble.SetVisibleText("");
		PlaceAtSelectedAnchor();
	}

	private void UpdateDemoTypewriter(float delta)
	{
		if (!_demoMode || _revealComplete || _waitingForChoice && _visibleCharacters >= _currentFullText.Length)
		{
			return;
		}

		_typeAccumulator += delta * DemoCharsPerSecond;
		var addedCharacters = (int)_typeAccumulator;
		if (addedCharacters <= 0)
		{
			return;
		}

		_typeAccumulator -= addedCharacters;
		_visibleCharacters = Mathf.Min(_currentFullText.Length, _visibleCharacters + addedCharacters);
		_bubble.SetVisibleText(_currentFullText[.._visibleCharacters]);
		if (_visibleCharacters >= _currentFullText.Length)
		{
			CompleteReveal();
		}
	}

	private void AdvanceDemoByClick()
	{
		if (!_demoMode)
		{
			StartDemo();
			return;
		}

		if (!_revealComplete)
		{
			_visibleCharacters = _currentFullText.Length;
			_bubble.SetVisibleText(_currentFullText);
			CompleteReveal();
			return;
		}

		if (_waitingForChoice)
		{
			return;
		}

		AdvanceDemoLine();
	}

	private void CompleteReveal()
	{
		_revealComplete = true;
		if (_waitingForChoice)
		{
			_bubble.ShowChoices(_choiceSamples);
			PlaceBubble();
		}
	}

	private void OnDemoChoiceSelected(int index)
	{
		_ = index;
		if (!_demoMode || !_waitingForChoice)
		{
			return;
		}

		_waitingForChoice = false;
		AdvanceDemoLine();
	}

	private void AdvanceDemoLine()
	{
		_demoIndex = (_demoIndex + 1) % _demoLines.Length;
		ShowDemoLine();
	}

	private void UpdateVisualDiagnostics()
	{
		if (_bubble == null || !_bubble.Visible)
		{
			return;
		}

		_bubbleBounds.Position = _bubble.Position;
		_bubbleBounds.Size = _bubble.Size;

		var viewportRect = new Rect2(_stage.GlobalPosition, _stage.Size);
		var bubbleRect = new Rect2(_bubble.GlobalPosition, _bubble.Size);
		var overflowLeft = Mathf.Max(0f, viewportRect.Position.X - bubbleRect.Position.X);
		var overflowTop = Mathf.Max(0f, viewportRect.Position.Y - bubbleRect.Position.Y);
		var overflowRight = Mathf.Max(0f, bubbleRect.End.X - viewportRect.End.X);
		var overflowBottom = Mathf.Max(0f, bubbleRect.End.Y - viewportRect.End.Y);
		var hasOverflow = overflowLeft + overflowTop + overflowRight + overflowBottom > 0.5f;
		var anchorName = _usingCustomAnchor ? "自定义" : PositionNames[_positionIndex];
		var sampleName = _textEditor.Text == SampleTexts[_sampleIndex] ? SampleNames[_sampleIndex] : "自定义";

		_scenarioLabel.Text = _demoMode
			? $"演示 {_demoIndex + 1}/{_demoLines.Length}：{sampleName} / {anchorName}"
			: $"手动：{sampleName} / {anchorName}";
		_diagnosticsLabel.Text =
			$"字符数：{_textEditor.Text.Length}\n" +
			$"锚点：{Mathf.Round(_anchorLocal.X)}, {Mathf.Round(_anchorLocal.Y)}\n" +
			$"主体：{Mathf.Round(_bubble.CurrentBodySize.X)} × {Mathf.Round(_bubble.CurrentBodySize.Y)}\n" +
			$"目标：{Mathf.Round(_bubble.TargetBodySize.X)} × {Mathf.Round(_bubble.TargetBodySize.Y)}\n" +
			$"整体：{Mathf.Round(_bubble.Size.X)} × {Mathf.Round(_bubble.Size.Y)}\n" +
			$"边界修正：{(_bubble.WasScreenClamped ? _bubble.ScreenClampOffset.ToString() : "无")}\n" +
			(hasOverflow
				? $"视口溢出：左 {Mathf.Round(overflowLeft)} / 上 {Mathf.Round(overflowTop)} / 右 {Mathf.Round(overflowRight)} / 下 {Mathf.Round(overflowBottom)}"
				: "视口溢出：无");
	}

	private static void ConfigureBubbleMousePassThrough(Node node)
	{
		if (node is Control control && node is not Button)
		{
			control.MouseFilter = MouseFilterEnum.Ignore;
		}

		foreach (var child in node.GetChildren())
		{
			ConfigureBubbleMousePassThrough(child);
		}
	}
}

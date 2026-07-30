using Godot;
using System;
using System.Collections.Generic;

namespace BXCQ.NarrRail;

/// <summary>
/// Adaptive world-anchored speech bubble. Owns text measurement, nine-patch layout,
/// resize animation and presentation only; story progression remains in the presenter.
/// </summary>
public partial class SpeechBubbleView : Control
{
	private const float TextHeightSafety = 6f;

	[ExportGroup("Width")]
	[Export] public float MaxBubbleWidth { get; set; } = 620f;

	[ExportGroup("Typography")]
	[Export] public int ChoiceFontSize { get; set; } = 18;

	[ExportGroup("Layout")]
	[Export] public float ChoiceGap { get; set; } = 10f;
	[Export] public float ChoiceRowGap { get; set; } = 6f;

	[ExportGroup("Screen Placement")]
	[Export] public float ScreenMargin { get; set; } = 16f;

	[ExportGroup("Animation")]
	[Export] public float ResizeDuration { get; set; } = 0.3f;
	[Export(PropertyHint.Range, "0,1,0.05")]
	public float TextFadeStartRatio { get; set; } = 0.58f;
	[Export] public float TextFadeDuration { get; set; } = 0.12f;

	private NinePatchRect _body = null!;
	private NinePatchRect _speakerPlate = null!;
	private Label _speakerLabel = null!;
	private Control _textClip = null!;
	private Label _bodyLabel = null!;
	private Control _choices = null!;
	private TextureRect _tail = null!;
	private Font _font = null!;
	private Tween _resizeTween = null!;

	private readonly List<Button> _choiceButtons = new();
	private string _layoutText = "";
	private Vector2 _currentBodySize = new(480f, 150f);
	private Vector2 _targetBodySize = new(480f, 150f);
	private float _measuredBodyTextHeight;
	private float _measuredChoicesHeight;
	private bool _hasScreenAnchor;
	private Vector2 _screenAnchor;
	private Rect2 _screenBounds;
	private Vector2 _sceneRootSize;
	private Vector2 _sceneBodySize;
	private float _contentPaddingLeft;
	private float _contentPaddingRight;
	private float _contentPaddingTop;
	private float _contentPaddingBottom;
	private int _bodyFontSize;

	public event Action<int> ChoiceSelected;

	public Vector2 CurrentBodySize => _currentBodySize;
	public Vector2 TargetBodySize => _targetBodySize;
	public float MinBubbleWidth => _sceneBodySize.X;
	public float MinBodyHeight => _sceneBodySize.Y;
	public bool IsResizing => _resizeTween != null && _resizeTween.IsRunning();
	public bool WasScreenClamped { get; private set; }
	public Vector2 ScreenClampOffset { get; private set; }
	public Vector2 TailTipLocalPosition => GetTailTipLocalPosition();
	public Vector2 TailTipGlobalPosition => GlobalPosition + GetTailTipLocalPosition();

	public override void _Ready()
	{
		MouseFilter = MouseFilterEnum.Ignore;
		_body = GetNode<NinePatchRect>("Body");
		_speakerPlate = GetNode<NinePatchRect>("SpeakerPlate");
		_speakerLabel = GetNode<Label>("SpeakerPlate/SpeakerLabel");
		_textClip = GetNode<Control>("TextClip");
		_bodyLabel = GetNode<Label>("TextClip/BodyLabel");
		_choices = GetNode<Control>("TextClip/Choices");
		_tail = GetNode<TextureRect>("Tail");
		_font = _bodyLabel.GetThemeFont("font");
		_bodyFontSize = _bodyLabel.GetThemeFontSize("font_size");
		_sceneRootSize = Size;
		_sceneBodySize = _body.Size;
		_contentPaddingLeft = _textClip.Position.X - _body.Position.X;
		_contentPaddingRight =
			(_body.Position.X + _body.Size.X) - (_textClip.Position.X + _textClip.Size.X);
		_contentPaddingTop = _textClip.Position.Y - _body.Position.Y;
		_contentPaddingBottom =
			(_body.Position.Y + _body.Size.Y) - (_textClip.Position.Y + _textClip.Size.Y);
		_currentBodySize = _body.Size;
		_targetBodySize = _currentBodySize;
		ApplyFont(_font);
		ApplyAnimatedBodySize(_currentBodySize);
		SetContentAlpha(1f);
		Visible = false;
	}

	public void ApplyFont(Font font)
	{
		_font = font ?? _bodyLabel?.GetThemeFont("font");
		if (_font == null || _speakerLabel == null)
		{
			return;
		}

		_bodyLabel.AddThemeFontOverride("font", _font);
		foreach (var button in _choiceButtons)
		{
			ApplyChoiceTheme(button);
		}

		if (Visible)
		{
			AnimateToMeasuredSize(fadeContent: false);
		}
	}

	/// <summary>
	/// Starts a new line. fullText is used for final wrapping and layout while the
	/// caller can independently stream the visible typewriter substring.
	/// </summary>
	public void BeginLine(string speaker, string fullText)
	{
		ClearChoiceNodes();
		_speakerLabel.Text = speaker ?? "";
		UpdateSpeakerVisibility();
		_layoutText = fullText ?? "";
		_bodyLabel.Text = "";
		Visible = true;
		AnimateToMeasuredSize(fadeContent: true);
	}

	/// <summary>Updates only glyphs; it deliberately does not trigger remeasurement.</summary>
	public void SetVisibleText(string visibleText)
	{
		_bodyLabel.Text = visibleText ?? "";
	}

	/// <summary>Compatibility helper for non-typewriter callers.</summary>
	public void ShowLine(string speaker, string text)
	{
		BeginLine(speaker, text);
		SetVisibleText(text);
	}

	public void ClearChoices()
	{
		if (_choiceButtons.Count == 0)
		{
			return;
		}

		ClearChoiceNodes();
		if (Visible)
		{
			AnimateToMeasuredSize(fadeContent: false);
		}
	}

	public void ShowChoices(string[] labels)
	{
		ClearChoiceNodes();
		if (labels is not { Length: > 0 })
		{
			AnimateToMeasuredSize(fadeContent: false);
			return;
		}

		for (var i = 0; i < labels.Length; i++)
		{
			var index = i;
			var button = new Button
			{
				Text = $"{index + 1}. {labels[i]}",
				Alignment = HorizontalAlignment.Left,
				MouseFilter = MouseFilterEnum.Stop,
			};
			ApplyChoiceTheme(button);
			button.Pressed += () => ChoiceSelected?.Invoke(index);
			_choices.AddChild(button);
			_choiceButtons.Add(button);
		}

		Visible = true;
		AnimateToMeasuredSize(fadeContent: true);
	}

	public void HideBubble()
	{
		_resizeTween?.Kill();
		_resizeTween = null!;
		ClearChoiceNodes();
		_hasScreenAnchor = false;
		WasScreenClamped = false;
		ScreenClampOffset = Vector2.Zero;
		Visible = false;
	}

	/// <summary>
	/// Called by the outer presenter every frame. The tail-tip anchor is the preferred
	/// placement; viewport containment wins when the preferred rect would be clipped.
	/// </summary>
	public void PlaceAtScreenAnchor(Vector2 screenAnchor, Vector2 viewportSize)
	{
		PlaceAtScreenAnchorInRect(screenAnchor, new Rect2(Vector2.Zero, viewportSize));
	}

	/// <summary>
	/// Placement variant for test stages or split-screen safe regions. This is the
	/// only runtime exception allowed to move the bubble root: child UI geometry
	/// remains entirely scene-authored.
	/// </summary>
	public void PlaceAtScreenAnchorInRect(Vector2 screenAnchor, Rect2 screenBounds)
	{
		_screenAnchor = screenAnchor;
		_screenBounds = screenBounds;
		_hasScreenAnchor = true;
		RepositionFromTailTip();
	}

	private void AnimateToMeasuredSize(bool fadeContent)
	{
		if (_font == null)
		{
			return;
		}

		_targetBodySize = MeasureTargetBodySize();
		_resizeTween?.Kill();
		_resizeTween = CreateTween();
		_resizeTween.SetParallel();

		if (fadeContent)
		{
			SetContentAlpha(0f);
		}

		_resizeTween
			.TweenMethod(Callable.From<Vector2>(ApplyAnimatedBodySize), _currentBodySize, _targetBodySize, ResizeDuration)
			.SetTrans(Tween.TransitionType.Cubic)
			.SetEase(Tween.EaseType.Out);

		if (fadeContent)
		{
			_resizeTween
				.TweenMethod(Callable.From<float>(SetContentAlpha), 0f, 1f, TextFadeDuration)
				.SetDelay(ResizeDuration * TextFadeStartRatio)
				.SetTrans(Tween.TransitionType.Quad)
				.SetEase(Tween.EaseType.Out);
		}
	}

	private Vector2 MeasureTargetBodySize()
	{
		var horizontalPadding = _contentPaddingLeft + _contentPaddingRight;
		var minContentWidth = Mathf.Max(1f, MinBubbleWidth - horizontalPadding);
		var maxContentWidth = Mathf.Max(minContentWidth, MaxBubbleWidth - horizontalPadding);
		var singleLineWidth = string.IsNullOrEmpty(_layoutText)
			? 0f
			: _font.GetStringSize(_layoutText, HorizontalAlignment.Left, -1f, _bodyFontSize).X;

		var widestChoice = 0f;
		var choiceRowHeight = _font.GetHeight(ChoiceFontSize) + 16f;
		foreach (var button in _choiceButtons)
		{
			widestChoice = Mathf.Max(
				widestChoice,
				_font.GetStringSize(button.Text, HorizontalAlignment.Left, -1f, ChoiceFontSize).X + 24f);
		}

		var desiredContentWidth = Mathf.Clamp(
			Mathf.Max(singleLineWidth, widestChoice),
			minContentWidth,
			maxContentWidth);
		_measuredBodyTextHeight = string.IsNullOrEmpty(_layoutText)
			? _font.GetHeight(_bodyFontSize)
			: _font.GetMultilineStringSize(
				_layoutText,
				HorizontalAlignment.Left,
				desiredContentWidth,
				_bodyFontSize).Y;
		_measuredBodyTextHeight += TextHeightSafety;

		_measuredChoicesHeight = _choiceButtons.Count == 0
			? 0f
			: _choiceButtons.Count * choiceRowHeight + (_choiceButtons.Count - 1) * ChoiceRowGap;
		var contentHeight = _measuredBodyTextHeight;
		if (_measuredChoicesHeight > 0f)
		{
			contentHeight += ChoiceGap + _measuredChoicesHeight;
		}

		var width = desiredContentWidth + horizontalPadding;
		var height = Mathf.Max(
			MinBodyHeight,
			_contentPaddingTop + contentHeight + _contentPaddingBottom);
		return new Vector2(width, height);
	}

	private void ApplyAnimatedBodySize(Vector2 size)
	{
		_currentBodySize = new Vector2(
			Mathf.Max(MinBubbleWidth, size.X),
			Mathf.Max(MinBodyHeight, size.Y));

		// The scene owns every child node's anchors and offsets. Runtime adaptation
		// changes only the root size; Godot applies the authored responsive layout.
		Size = _sceneRootSize + (_currentBodySize - _sceneBodySize);
		_body.PivotOffset = new Vector2(_currentBodySize.X * 0.5f, _currentBodySize.Y);

		var contentWidth = Mathf.Max(1f, _currentBodySize.X - _contentPaddingLeft - _contentPaddingRight);
		_bodyLabel.OffsetBottom = _measuredBodyTextHeight;

		var choicesY = _measuredBodyTextHeight + (_choiceButtons.Count > 0 ? ChoiceGap : 0f);
		_choices.OffsetTop = choicesY;
		_choices.OffsetBottom = choicesY + _measuredChoicesHeight;
		LayoutChoiceButtons(contentWidth);
		UpdateSpeakerVisibility();

		if (_hasScreenAnchor)
		{
			RepositionFromTailTip();
		}
		else
		{
			LayoutTailAndPivot();
		}
	}

	/// <summary>
	/// Speaker plate geometry is authored entirely in the scene. Runtime code may
	/// change only its content state, never its position or size.
	/// </summary>
	private void UpdateSpeakerVisibility()
	{
		var hasSpeaker = !string.IsNullOrWhiteSpace(_speakerLabel.Text);
		_speakerPlate.Visible = hasSpeaker;
		_speakerLabel.Visible = hasSpeaker;
	}

	private void LayoutChoiceButtons(float contentWidth)
	{
		var y = 0f;
		var rowHeight = _font.GetHeight(ChoiceFontSize) + 16f;
		foreach (var button in _choiceButtons)
		{
			button.Position = new Vector2(0f, y);
			button.Size = new Vector2(contentWidth, rowHeight);
			y += rowHeight + ChoiceRowGap;
		}
	}

	private void RepositionFromTailTip()
	{
		LayoutTailAndPivot();
		var preferredPosition = _screenAnchor - GetTailTipLocalPosition();
		var resolvedPosition = ClampBubblePosition(preferredPosition, _screenBounds);
		ScreenClampOffset = resolvedPosition - preferredPosition;
		WasScreenClamped = ScreenClampOffset.LengthSquared() > 0.01f;
		GlobalPosition = resolvedPosition;
	}

	private Vector2 ClampBubblePosition(Vector2 preferredPosition, Rect2 bounds)
	{
		var margin = Mathf.Max(0f, ScreenMargin);
		var safeMin = bounds.Position + new Vector2(margin, margin);
		var safeMax = bounds.Position + bounds.Size - new Vector2(margin, margin) - Size;

		// Normal game viewports are larger than the bubble. If a debug viewport is
		// smaller, pin to its safe origin; the content remains deterministic instead
		// of oscillating between contradictory min/max constraints.
		var resolvedX = safeMax.X >= safeMin.X
			? Mathf.Clamp(preferredPosition.X, safeMin.X, safeMax.X)
			: safeMin.X;
		var resolvedY = safeMax.Y >= safeMin.Y
			? Mathf.Clamp(preferredPosition.Y, safeMin.Y, safeMax.Y)
			: safeMin.Y;
		return new Vector2(resolvedX, resolvedY);
	}

	private void LayoutTailAndPivot()
	{
		var tipXInTail = _tail.Size.X * 0.02f;
		var tipYInTail = _tail.Size.Y * 0.98f;
		_tail.PivotOffset = new Vector2(tipXInTail, tipYInTail);
		PivotOffset = GetTailTipLocalPosition();
	}

	private Vector2 GetTailTipLocalPosition()
	{
		return _tail.Position + new Vector2(_tail.Size.X * 0.02f, _tail.Size.Y * 0.98f);
	}

	private void ApplyChoiceTheme(Button button)
	{
		button.AddThemeFontOverride("font", _font);
		button.AddThemeFontSizeOverride("font_size", ChoiceFontSize);
		button.AddThemeColorOverride("font_color", new Color(0.18f, 0.12f, 0.065f));
		button.AddThemeColorOverride("font_hover_color", new Color(0.12f, 0.09f, 0.05f));

		var normal = new StyleBoxFlat
		{
			BgColor = new Color(0.79f, 0.75f, 0.57f, 0.72f),
			CornerRadiusTopLeft = 3,
			CornerRadiusTopRight = 3,
			CornerRadiusBottomLeft = 3,
			CornerRadiusBottomRight = 3,
			ContentMarginLeft = 10f,
			ContentMarginRight = 10f,
			ContentMarginTop = 6f,
			ContentMarginBottom = 6f,
		};
		var hover = normal.Duplicate() as StyleBoxFlat;
		hover!.BgColor = new Color(0.52f, 0.58f, 0.44f, 0.88f);
		button.AddThemeStyleboxOverride("normal", normal);
		button.AddThemeStyleboxOverride("hover", hover);
		button.AddThemeStyleboxOverride("pressed", hover);
	}

	private void SetContentAlpha(float alpha)
	{
		var value = Mathf.Clamp(alpha, 0f, 1f);
		_speakerLabel.Modulate = WithAlpha(_speakerLabel.Modulate, value);
		_textClip.Modulate = WithAlpha(_textClip.Modulate, value);
	}

	private void ClearChoiceNodes()
	{
		foreach (var button in _choiceButtons)
		{
			_choices.RemoveChild(button);
			button.QueueFree();
		}
		_choiceButtons.Clear();
		_measuredChoicesHeight = 0f;
	}

	private static Color WithAlpha(Color color, float alpha) =>
		new(color.R, color.G, color.B, alpha);

}

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
	// All four art layers were authored on one 3100x2149 canvas. The dialogue
	// paper is the only freely stretched layer; ornamental pieces use one uniform
	// art scale so their painted proportions stay faithful to the reference.
	private const float ReferenceBodyWidth = 2719f;
	private const float ReferenceBodyHeight = 1355f;
	private const float BodyX = 188f;
	private const float BodyY = 392f;
	private const float SpeakerX = 549f;
	private const float SpeakerY = 0f;
	private const float SpeakerWidth = 1980f;
	private const float SpeakerHeight = 484f;
	private const float LeftScrollX = 0f;
	private const float LeftScrollY = 281f;
	private const float LeftScrollWidth = 281f;
	private const float LeftScrollHeight = 1617f;
	private const float LeftScrollTopCropHeight = 132f;
	private const float LeftScrollBottomCropHeight = 136f;
	private const float LeftScrollCropWidth = 128f;
	private const float TailX = 1989f;
	private const float TailY = 1014f;
	private const float TailWidth = 1083f;
	private const float TailHeight = 1115f;
	private const float CompositionWidth = 3072f;
	private const float TailBodyYRatio = (TailY - BodyY) / ReferenceBodyHeight;
	private const float LeftScrollTopOverhang = BodyY - LeftScrollY;
	private const float LeftScrollBottomOverhang =
		(LeftScrollY + LeftScrollHeight) - (BodyY + ReferenceBodyHeight);
	private const float TextHeightSafety = 6f;

	[ExportGroup("Width")]
	[Export] public float MinBubbleWidth { get; set; } = 480f;
	[Export] public float MaxBubbleWidth { get; set; } = 620f;
	[Export] public float MinBodyHeight { get; set; } = 150f;

	[ExportGroup("Typography")]
	[Export] public int SpeakerFontSize { get; set; } = 18;
	[Export] public int BodyFontSize { get; set; } = 22;
	[Export] public int ChoiceFontSize { get; set; } = 18;

	[ExportGroup("Layout")]
	[Export] public float ContentPaddingLeft { get; set; } = 40f;
	[Export] public float ContentPaddingRight { get; set; } = 40f;
	[Export] public float ContentPaddingTop { get; set; } = 44f;
	[Export] public float ContentPaddingBottom { get; set; } = 36f;
	[Export] public float ChoiceGap { get; set; } = 10f;
	[Export] public float ChoiceRowGap { get; set; } = 6f;
	[Export] public Vector2 ShadowOffset { get; set; } = new(8f, 10f);

	[ExportGroup("Animation")]
	[Export] public float ResizeDuration { get; set; } = 0.3f;
	[Export(PropertyHint.Range, "0,1,0.05")]
	public float TextFadeStartRatio { get; set; } = 0.58f;
	[Export] public float TextFadeDuration { get; set; } = 0.12f;

	private NinePatchRect _shadow = null!;
	private NinePatchRect _body = null!;
	private NinePatchRect _speakerPlate = null!;
	private Label _speakerLabel = null!;
	private Control _leftScroll = null!;
	private TextureRect _leftScrollTop = null!;
	private TextureRect _leftScrollMiddle = null!;
	private TextureRect _leftScrollBottom = null!;
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

	public event Action<int> ChoiceSelected;

	public Vector2 CurrentBodySize => _currentBodySize;
	public Vector2 TargetBodySize => _targetBodySize;
	public bool IsResizing => _resizeTween != null && _resizeTween.IsRunning();
	public Vector2 TailTipLocalPosition => GetTailTipLocalPosition();
	public Vector2 TailTipGlobalPosition => GlobalPosition + GetTailTipLocalPosition();

	public override void _Ready()
	{
		MouseFilter = MouseFilterEnum.Ignore;
		_shadow = GetNode<NinePatchRect>("Shadow");
		_body = GetNode<NinePatchRect>("Body");
		_speakerPlate = GetNode<NinePatchRect>("SpeakerPlate");
		_speakerLabel = GetNode<Label>("SpeakerPlate/SpeakerLabel");
		_leftScroll = GetNode<Control>("LeftScroll");
		_leftScrollTop = GetNode<TextureRect>("LeftScroll/Top");
		_leftScrollMiddle = GetNode<TextureRect>("LeftScroll/Middle");
		_leftScrollBottom = GetNode<TextureRect>("LeftScroll/Bottom");
		_textClip = GetNode<Control>("TextClip");
		_bodyLabel = GetNode<Label>("TextClip/BodyLabel");
		_choices = GetNode<Control>("TextClip/Choices");
		_tail = GetNode<TextureRect>("Tail");
		_font = _bodyLabel.GetThemeFont("font");
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

		_speakerLabel.AddThemeFontOverride("font", _font);
		_bodyLabel.AddThemeFontOverride("font", _font);
		_speakerLabel.AddThemeFontSizeOverride("font_size", SpeakerFontSize);
		_bodyLabel.AddThemeFontSizeOverride("font_size", BodyFontSize);
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
		Visible = false;
	}

	/// <summary>
	/// Called by the outer presenter every frame. Recomputes the root transform from
	/// the animated tail-tip position, so resizing never detaches the tail from speaker.
	/// </summary>
	public void PlaceAtScreenAnchor(Vector2 screenAnchor, Vector2 viewportSize)
	{
		_screenAnchor = screenAnchor;
		_ = viewportSize;
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
		var horizontalPadding = ContentPaddingLeft + ContentPaddingRight;
		var minContentWidth = Mathf.Max(1f, MinBubbleWidth - horizontalPadding);
		var maxContentWidth = Mathf.Max(minContentWidth, MaxBubbleWidth - horizontalPadding);
		var singleLineWidth = string.IsNullOrEmpty(_layoutText)
			? 0f
			: _font.GetStringSize(_layoutText, HorizontalAlignment.Left, -1f, BodyFontSize).X;

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
			? _font.GetHeight(BodyFontSize)
			: _font.GetMultilineStringSize(
				_layoutText,
				HorizontalAlignment.Left,
				desiredContentWidth,
				BodyFontSize).Y;
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
			ContentPaddingTop + contentHeight + ContentPaddingBottom);
		return new Vector2(width, height);
	}

	private void ApplyAnimatedBodySize(Vector2 size)
	{
		_currentBodySize = new Vector2(
			Mathf.Max(MinBubbleWidth, size.X),
			Mathf.Max(MinBodyHeight, size.Y));

		var artScale = _currentBodySize.X / ReferenceBodyWidth;
		var bodyPosition = ScaleReference(BodyX, BodyY, artScale);

		_body.Position = bodyPosition;
		_body.Size = _currentBodySize;
		_body.PivotOffset = new Vector2(_currentBodySize.X * 0.5f, _currentBodySize.Y);
		_shadow.Position = bodyPosition + ShadowOffset;
		_shadow.Size = _currentBodySize;
		_shadow.PivotOffset = _body.PivotOffset;
		_speakerPlate.Position = ScaleReference(SpeakerX, SpeakerY, artScale);
		_speakerPlate.Size = ScaleReference(SpeakerWidth, SpeakerHeight, artScale);
		LayoutLeftScroll(bodyPosition, artScale);
		_tail.Position = new Vector2(
			TailX * artScale,
			bodyPosition.Y + _currentBodySize.Y * TailBodyYRatio);
		_tail.Size = ScaleReference(TailWidth, TailHeight, artScale);
		_tail.FlipH = false;

		var contentWidth = Mathf.Max(1f, _currentBodySize.X - ContentPaddingLeft - ContentPaddingRight);
		var contentHeight = Mathf.Max(1f, _currentBodySize.Y - ContentPaddingTop - ContentPaddingBottom);
		_textClip.Position = bodyPosition + new Vector2(ContentPaddingLeft, ContentPaddingTop);
		_textClip.Size = new Vector2(contentWidth, contentHeight);
		_bodyLabel.Position = Vector2.Zero;
		_bodyLabel.Size = new Vector2(contentWidth, _measuredBodyTextHeight);

		var choicesY = _measuredBodyTextHeight + (_choiceButtons.Count > 0 ? ChoiceGap : 0f);
		_choices.Position = new Vector2(0f, choicesY);
		_choices.Size = new Vector2(contentWidth, _measuredChoicesHeight);
		LayoutChoiceButtons(contentWidth);
		LayoutSpeakerPlate();

		var compositionBottom = Mathf.Max(
			_body.Position.Y + _body.Size.Y,
			Mathf.Max(
				_leftScroll.Position.Y + _leftScroll.Size.Y,
				_tail.Position.Y + _tail.Size.Y));
		Size = new Vector2(CompositionWidth * artScale, compositionBottom);
		if (_hasScreenAnchor)
		{
			RepositionFromTailTip();
		}
		else
		{
			LayoutTailAndPivot();
		}
	}

	private void LayoutLeftScroll(Vector2 bodyPosition, float artScale)
	{
		var scrollWidth = LeftScrollWidth * artScale;
		var scrollHeight = _currentBodySize.Y
			+ (LeftScrollTopOverhang + LeftScrollBottomOverhang) * artScale;
		_leftScroll.Position = new Vector2(
			LeftScrollX * artScale,
			bodyPosition.Y - LeftScrollTopOverhang * artScale);
		_leftScroll.Size = new Vector2(scrollWidth, scrollHeight);

		var textureScale = scrollWidth / LeftScrollCropWidth;
		var topHeight = LeftScrollTopCropHeight * textureScale;
		var bottomHeight = LeftScrollBottomCropHeight * textureScale;
		var middleHeight = Mathf.Max(1f, scrollHeight - topHeight - bottomHeight);

		_leftScrollTop.Position = Vector2.Zero;
		_leftScrollTop.Size = new Vector2(scrollWidth, topHeight);
		_leftScrollMiddle.Position = new Vector2(0f, topHeight);
		_leftScrollMiddle.Size = new Vector2(scrollWidth, middleHeight);
		_leftScrollBottom.Position = new Vector2(0f, topHeight + middleHeight);
		_leftScrollBottom.Size = new Vector2(scrollWidth, bottomHeight);
	}

	private void LayoutSpeakerPlate()
	{
		var hasSpeaker = !string.IsNullOrWhiteSpace(_speakerLabel.Text);
		_speakerPlate.Visible = hasSpeaker;
		_speakerLabel.Visible = hasSpeaker;
		if (!hasSpeaker)
		{
			return;
		}

		var horizontalInset = _speakerPlate.Size.X * 0.08f;
		var verticalInset = _speakerPlate.Size.Y * 0.1f;
		_speakerLabel.Position = _speakerPlate.Position + new Vector2(horizontalInset, verticalInset);
		_speakerLabel.Size = new Vector2(
			Mathf.Max(1f, _speakerPlate.Size.X - horizontalInset * 2f),
			Mathf.Max(1f, _speakerPlate.Size.Y - verticalInset * 2f));
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
		GlobalPosition = _screenAnchor - GetTailTipLocalPosition();
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

	private static Vector2 ScaleReference(float x, float y, float scale) =>
		new(x * scale, y * scale);
}

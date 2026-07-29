using Godot;
using System;

namespace BXCQ.NarrRail;

/// <summary>World-projected placeholder dialogue bubble with optional choice rows.</summary>
public partial class SpeechBubbleView : Control
{
	private PanelContainer _panel = null!;
	private VBoxContainer _vbox = null!;
	private Label _speakerLabel = null!;
	private Label _bodyLabel = null!;
	private VBoxContainer _choicesBox = null!;
	private ColorRect _tail = null!;
	private Font _font = null!;

	public event Action<int> ChoiceSelected;

	public override void _Ready()
	{
		MouseFilter = MouseFilterEnum.Ignore;
		Build();
		Visible = false;
	}

	public void ApplyFont(Font font)
	{
		_font = font;
		if (font == null || _speakerLabel == null)
		{
			return;
		}

		_speakerLabel.AddThemeFontOverride("font", font);
		_bodyLabel.AddThemeFontOverride("font", font);
		_speakerLabel.AddThemeFontSizeOverride("font_size", 18);
		_bodyLabel.AddThemeFontSizeOverride("font_size", 20);
	}

	public void ShowLine(string speaker, string visibleText)
	{
		_speakerLabel.Text = speaker;
		_bodyLabel.Text = visibleText;
		Visible = true;
		RefreshSize();
	}

	public void ClearChoices()
	{
		foreach (var child in _choicesBox.GetChildren())
		{
			child.QueueFree();
		}

		_choicesBox.Visible = false;
		RefreshSize();
	}

	public void ShowChoices(string[] labels)
	{
		ClearChoices();
		_choicesBox.Visible = labels is { Length: > 0 };
		if (!_choicesBox.Visible)
		{
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
			if (_font != null)
			{
				button.AddThemeFontOverride("font", _font);
				button.AddThemeFontSizeOverride("font_size", 18);
			}

			var normal = new StyleBoxFlat
			{
				BgColor = new Color(0.86f, 0.8f, 0.64f, 0.95f),
				ContentMarginLeft = 8,
				ContentMarginTop = 4,
				ContentMarginRight = 8,
				ContentMarginBottom = 4,
			};
			var hover = normal.Duplicate() as StyleBoxFlat;
			hover!.BgColor = new Color(0.78f, 0.7f, 0.5f, 1f);
			button.AddThemeStyleboxOverride("normal", normal);
			button.AddThemeStyleboxOverride("hover", hover);
			button.AddThemeStyleboxOverride("pressed", hover);
			button.AddThemeColorOverride("font_color", new Color(0.2f, 0.12f, 0.05f));
			button.Pressed += () => ChoiceSelected?.Invoke(index);
			_choicesBox.AddChild(button);
		}

		RefreshSize();
	}

	public void HideBubble()
	{
		ClearChoices();
		Visible = false;
	}

	public void PlaceAtScreenAnchor(Vector2 screenAnchor, Vector2 viewportSize)
	{
		RefreshSize();
		var size = Size;
		var desired = screenAnchor + new Vector2(-size.X * 0.5f, -size.Y - 14f);
		const float margin = 24f;
		desired.X = Mathf.Clamp(desired.X, margin, Mathf.Max(margin, viewportSize.X - size.X - margin));
		desired.Y = Mathf.Clamp(desired.Y, margin, Mathf.Max(margin, viewportSize.Y - size.Y - margin));
		GlobalPosition = desired;

		var localX = Mathf.Clamp(screenAnchor.X - GlobalPosition.X, 20f, Mathf.Max(36f, size.X - 20f));
		_tail.Position = new Vector2(localX - 8f, size.Y - 10f);
	}

	private void RefreshSize()
	{
		_panel.ResetSize();
		Size = _panel.GetCombinedMinimumSize() + new Vector2(0, 12);
	}

	private void Build()
	{
		_panel = new PanelContainer { MouseFilter = MouseFilterEnum.Ignore };
		var style = new StyleBoxFlat
		{
			BgColor = new Color(0.93f, 0.88f, 0.74f, 0.96f),
			BorderColor = new Color(0.45f, 0.32f, 0.18f, 1f),
			BorderWidthLeft = 2,
			BorderWidthTop = 2,
			BorderWidthRight = 2,
			BorderWidthBottom = 2,
			CornerRadiusTopLeft = 6,
			CornerRadiusTopRight = 6,
			CornerRadiusBottomRight = 6,
			CornerRadiusBottomLeft = 6,
			ContentMarginLeft = 14,
			ContentMarginTop = 10,
			ContentMarginRight = 14,
			ContentMarginBottom = 10,
		};
		_panel.AddThemeStyleboxOverride("panel", style);
		AddChild(_panel);

		_vbox = new VBoxContainer { MouseFilter = MouseFilterEnum.Ignore };
		_panel.AddChild(_vbox);

		_speakerLabel = new Label
		{
			MouseFilter = MouseFilterEnum.Ignore,
			Modulate = new Color(0.35f, 0.22f, 0.12f),
		};
		_bodyLabel = new Label
		{
			AutowrapMode = TextServer.AutowrapMode.WordSmart,
			MouseFilter = MouseFilterEnum.Ignore,
			Modulate = new Color(0.15f, 0.1f, 0.06f),
			CustomMinimumSize = new Vector2(300, 0),
		};
		_choicesBox = new VBoxContainer
		{
			Visible = false,
			MouseFilter = MouseFilterEnum.Stop,
		};
		_vbox.AddChild(_speakerLabel);
		_vbox.AddChild(_bodyLabel);
		_vbox.AddChild(_choicesBox);

		_tail = new ColorRect
		{
			Color = new Color(0.93f, 0.88f, 0.74f, 0.96f),
			Size = new Vector2(16, 16),
			Rotation = Mathf.DegToRad(45),
			MouseFilter = MouseFilterEnum.Ignore,
		};
		AddChild(_tail);
	}
}

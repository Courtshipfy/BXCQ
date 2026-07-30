using Godot;
using BXCQ.NarrRail;
using BXCQ.Player;

namespace BXCQ.Interaction;

public partial class InteractableProp : Area2D, IInteractable, ISpeakerAnchor
{
	private static readonly Color HoverPerson = new(1.28f, 1.1f, 0.75f, 1f);
	private static readonly Color HoverExamine = new(0.95f, 1.15f, 1.25f, 1f);
	private static readonly Color NearPerson = new(1.12f, 1.05f, 0.88f, 1f);

	[Export] public string PromptName { get; set; } = "Object";
	[Export] public InteractionRole Role { get; set; } = InteractionRole.Unconfigured;
	[Export] public float ApproachOffsetX { get; set; } = 48f;
	[Export] public string NarrRailStoryPath { get; set; } = "";
	[Export] public string ExamineText { get; set; } = "";
	[Export] public string SpeakerId { get; set; } = "";
	[Export] public Vector2 BubbleOffset { get; set; } = new(0, -52);
	[Export] public float ProximityHintRange { get; set; } = 110f;

	private Color _baseModulate = Colors.White;
	private Vector2 _baseScale = Vector2.One;
	private bool _hovering;
	private bool _configurationValid;
	private Label _label = null!;

	public Vector2 AnchorGlobalPosition => GlobalPosition + BubbleOffset;
	public string DisplayName => PromptName;

	public bool IsPerson => Role == InteractionRole.Person;
	public bool IsExamineProp => Role == InteractionRole.Examine;
	public bool IsInvestigateProp => Role == InteractionRole.Investigate;

	public override void _Ready()
	{
		CollisionLayer = 2;
		CollisionMask = 0;
		Monitoring = false;
		Monitorable = true;
		InputPickable = true;
		_baseModulate = Modulate;
		_baseScale = Scale;
		_configurationValid = ValidateConfiguration();
		AddToGroup("interactables");
		if (!string.IsNullOrWhiteSpace(SpeakerId))
		{
			AddToGroup("speakers");
		}

		MouseEntered += OnMouseEntered;
		MouseExited += OnMouseExited;

		_label = GetNodeOrNull<Label>("Label");
		RefreshPromptLabel();
	}

	InteractionPlan IInteractable.PlanInteraction(PlayerController player)
	{
		return CanInteract()
			? InteractionPlan.ApproachFromHorizontal(this, player.GlobalPosition, ApproachOffsetX)
			: InteractionPlan.Unavailable;
	}

	bool IInteractable.TryExecuteInteraction(PlayerController player)
	{
		if (!CanInteract())
		{
			return false;
		}

		var started = false;
		if (IsExamineProp)
		{
			var presenter = GetTree().GetFirstNodeInGroup("dialogue_presenter") as DialoguePresenter;
			started = presenter != null && presenter.ShowExamine(AnchorGlobalPosition, "查看", ExamineText);
		}
		else if (!string.IsNullOrWhiteSpace(NarrRailStoryPath))
		{
			started = GetNode<NarrRailExecution>("/root/NarrRailExecution").StartStory(NarrRailStoryPath);
		}

		if (!started)
		{
			return false;
		}

		if (IsPerson)
		{
			player.FaceToward(GlobalPosition);
		}

		GD.Print($"Interact: {PromptName} ({DescribeRole()})");
		Modulate = IsExamineProp ? HoverExamine : HoverPerson;
		Scale = _baseScale * 1.12f;
		var tween = CreateTween().SetParallel(true);
		tween.TweenProperty(this, "modulate", _baseModulate, 0.45).SetDelay(0.15);
		tween.TweenProperty(this, "scale", _baseScale, 0.45).SetDelay(0.15);
		return true;
	}

	public string DescribeRole()
	{
		return Role switch
		{
			InteractionRole.Person => "person",
			InteractionRole.Examine => "examine",
			InteractionRole.Investigate => "investigate",
			_ => "unconfigured",
		};
	}

	private bool ValidateConfiguration()
	{
		var hasStory = !string.IsNullOrWhiteSpace(NarrRailStoryPath);
		var hasExamineText = !string.IsNullOrWhiteSpace(ExamineText);
		var valid = Role switch
		{
			InteractionRole.Person => hasStory && !hasExamineText && !string.IsNullOrWhiteSpace(SpeakerId),
			InteractionRole.Examine => !hasStory && hasExamineText,
			InteractionRole.Investigate => hasStory && !hasExamineText,
			_ => false,
		};

		if (!valid)
		{
			GD.PushError(
				$"InteractableProp '{GetPath()}' has invalid {Role} configuration: " +
				$"story={hasStory}, examine_text={hasExamineText}, speaker='{SpeakerId}'.");
		}

		return valid;
	}

	private bool CanInteract()
	{
		var gameState = GetNodeOrNull<GameState>("/root/GameState");
		return _configurationValid && (gameState == null || !gameState.IsDialogueBlocking);
	}

	private void OnMouseEntered()
	{
		_hovering = true;
		RefreshVisualState();
	}

	private void OnMouseExited()
	{
		_hovering = false;
		RefreshVisualState();
	}

	public override void _Process(double delta)
	{
		RefreshVisualState();
	}

	private void RefreshVisualState()
	{
		RefreshPromptLabel();

		var player = GetTree().GetFirstNodeInGroup("player") as PlayerController;
		if (player == null || !CanInteract())
		{
			Modulate = _baseModulate;
			return;
		}

		if (_hovering)
		{
			Modulate = IsExamineProp ? HoverExamine : HoverPerson;
			return;
		}

		// In-range hint for people only; no separate key-prompt bar.
		if (IsPerson && GlobalPosition.DistanceTo(player.GlobalPosition) <= ProximityHintRange)
		{
			Modulate = NearPerson;
			return;
		}

		Modulate = _baseModulate;
	}

	private void RefreshPromptLabel()
	{
		if (_label == null)
		{
			return;
		}

		_label.MouseFilter = Control.MouseFilterEnum.Ignore;
		_label.Text = DescribeRole() switch
		{
			"examine" => $"查看 · {PromptName}",
			"person" => $"交谈 · {PromptName}",
			"investigate" => $"调查 · {PromptName}",
			_ => PromptName,
		};
	}
}

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
	[Export] public float ApproachOffsetX { get; set; } = 48f;
	[Export] public string NarrRailStoryPath { get; set; } = "";
	[Export] public string ExamineText { get; set; } = "";
	[Export] public string SpeakerId { get; set; } = "";
	[Export] public Vector2 BubbleOffset { get; set; } = new(0, -52);
	[Export] public float ProximityHintRange { get; set; } = 110f;
	/// <summary>Mark NPCs for talk affordance (face-toward, 交谈 label, near hint). Notice boards stay false.</summary>
	[Export] public bool IsNpcCharacter { get; set; }

	private Color _baseModulate = Colors.White;
	private Vector2 _baseScale = Vector2.One;
	private bool _hovering;
	private Label _label = null!;

	public Vector2 AnchorGlobalPosition => GlobalPosition + BubbleOffset;

	/// <summary>Person: an NPC that starts a full NarrRail conversation.</summary>
	public bool IsPerson => IsNpcCharacter && !IsExamineProp;

	public bool IsExamineProp => !string.IsNullOrWhiteSpace(ExamineText);

	public override void _Ready()
	{
		CollisionLayer = 2;
		CollisionMask = 0;
		Monitoring = false;
		Monitorable = true;
		InputPickable = true;
		_baseModulate = Modulate;
		_baseScale = Scale;
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

	public bool CanInteract(PlayerController player)
	{
		var gameState = GetNodeOrNull<GameState>("/root/GameState");
		return gameState == null || !gameState.IsDialogueBlocking;
	}

	public void Interact(PlayerController player)
	{
		if (!CanInteract(player))
		{
			return;
		}

		GD.Print($"Interact: {PromptName} ({DescribeRole()})");
		Modulate = IsExamineProp ? HoverExamine : HoverPerson;
		Scale = _baseScale * 1.12f;

		var tween = CreateTween();
		tween.SetParallel(true);
		tween.TweenProperty(this, "modulate", _baseModulate, 0.45)
			.SetDelay(0.15);
		tween.TweenProperty(this, "scale", _baseScale, 0.45)
			.SetDelay(0.15);

		var presenter = GetTree().GetFirstNodeInGroup("dialogue_presenter") as DialoguePresenter;
		if (presenter == null)
		{
			GD.PushWarning("InteractableProp: DialoguePresenter not found");
			return;
		}

		if (IsExamineProp)
		{
			// A fixed title distinguishes one-shot Examine text from character dialogue.
			presenter.ShowExamine(AnchorGlobalPosition, "查看", ExamineText);
			return;
		}

		if (string.IsNullOrWhiteSpace(NarrRailStoryPath))
		{
			return;
		}

		presenter.StartStory(NarrRailStoryPath);
	}

	public Vector2 GetInteractionPoint(PlayerController player)
	{
		var side = player.GlobalPosition.X <= GlobalPosition.X ? -1f : 1f;
		return new Vector2(GlobalPosition.X + side * ApproachOffsetX, GlobalPosition.Y);
	}

	public string DescribeRole()
	{
		if (IsExamineProp)
		{
			return "examine";
		}

		if (IsPerson)
		{
			return "person";
		}

		if (!string.IsNullOrWhiteSpace(NarrRailStoryPath))
		{
			return "investigate";
		}

		return "prop";
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
		if (player == null || !CanInteract(player))
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

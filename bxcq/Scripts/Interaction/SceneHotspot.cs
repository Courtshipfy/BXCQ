using Godot;
using BXCQ.NarrRail;
using BXCQ.Player;

namespace BXCQ.Interaction;

public partial class SceneHotspot : Area2D, IInteractable
{
	[Export] public string PromptName { get; set; } = "Door";
	[Export] public string HotspotId { get; set; } = "";
	[Export] public string TargetScenePath { get; set; } = GameState.VillageScenePath;
	[Export] public string TargetSpawnId { get; set; } = "default";
	[Export] public float ApproachOffsetX { get; set; } = 48f;
	[Export] public bool IsEnabled { get; set; } = true;
	/// <summary>If set, the hotspot is enabled only when this NarrRail variable is true.</summary>
	[Export] public string RequiredStoryBool { get; set; } = "";

	private Color _baseModulate = Colors.White;
	private bool _hovering;
	public string DisplayName => PromptName;
	public bool IsAvailable => CanInteract();

	public override void _Ready()
	{
		CollisionLayer = 2;
		CollisionMask = 0;
		Monitoring = false;
		Monitorable = true;
		InputPickable = true;
		_baseModulate = Modulate;
		AddToGroup("interactables");
		AddToGroup("scene_hotspots");
		if (string.IsNullOrWhiteSpace(HotspotId))
		{
			HotspotId = Name;
		}

		var gameState = GetNodeOrNull<GameState>("/root/GameState");
		if (gameState != null && gameState.HasHotspotOverride(HotspotId))
		{
			IsEnabled = gameState.IsHotspotEnabled(HotspotId, IsEnabled);
		}

		MouseEntered += OnMouseEntered;
		MouseExited += OnMouseExited;

		if (GetNodeOrNull<Label>("Label") is { } label)
		{
			label.Text = PromptName;
			label.MouseFilter = Control.MouseFilterEnum.Ignore;
		}
	}

	public bool MatchesHotspotId(string hotspotId) =>
		string.Equals(HotspotId, hotspotId, System.StringComparison.Ordinal);

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

		GD.Print($"Hotspot -> {TargetScenePath} spawn={TargetSpawnId}");
		GetNode<SceneTransition>("/root/SceneTransition").GoTo(TargetScenePath, TargetSpawnId);
		return true;
	}

	private bool CanInteract()
	{
		if (!IsEnabled)
		{
			return false;
		}

		var gameState = GetNodeOrNull<GameState>("/root/GameState");
		if (gameState != null && gameState.IsDialogueBlocking)
		{
			return false;
		}

		if (!string.IsNullOrWhiteSpace(RequiredStoryBool))
		{
			var bridge = GetNodeOrNull<NarrRailBridge>("/root/NarrRailBridge");
			if (bridge == null || !bridge.GetBool(RequiredStoryBool, false))
			{
				return false;
			}
		}

		return true;
	}

	private void OnMouseEntered()
	{
		_hovering = true;
		RefreshHoverVisual();
	}

	private void OnMouseExited()
	{
		_hovering = false;
		Modulate = _baseModulate;
	}

	private void RefreshHoverVisual()
	{
		if (!_hovering)
		{
			return;
		}

		var player = GetTree().GetFirstNodeInGroup("player") as PlayerController;
		if (player == null || !CanInteract())
		{
			Modulate = _baseModulate;
			return;
		}

		Modulate = new Color(1.2f, 1.12f, 0.85f, 1f);
	}

	public override void _Process(double delta)
	{
		if (_hovering)
		{
			RefreshHoverVisual();
		}
	}
}

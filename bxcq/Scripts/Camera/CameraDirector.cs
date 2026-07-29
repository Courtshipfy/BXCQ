using Godot;

namespace BXCQ.CameraSystem;

public partial class CameraDirector : Node
{
	[Export] public float FadeDuration { get; set; } = 0.28f;
	[Export] public NodePath FadeRectPath { get; set; } = "FadeLayer/FadeRect";

	private ColorRect _fadeRect = null!;
	private Camera2D _activeCamera = null!;
	private bool _isSwitching;

	public string CurrentZoneName { get; private set; } = "Center";

	public override void _Ready()
	{
		AddToGroup("camera_director");
		_fadeRect = GetNode<ColorRect>(FadeRectPath);
		_fadeRect.Color = new Color(0f, 0f, 0f, 0f);
		_fadeRect.MouseFilter = Control.MouseFilterEnum.Ignore;
	}

	public void RegisterInitialCamera(Camera2D camera, string zoneName)
	{
		_activeCamera = camera;
		CurrentZoneName = zoneName;
		camera.MakeCurrent();
		var gameState = GetNodeOrNull<GameState>("/root/GameState");
		if (gameState != null)
		{
			gameState.CurrentZoneName = zoneName;
		}
	}

	public void RequestZone(CameraZone zone)
	{
		if (_isSwitching || zone.Camera == _activeCamera)
		{
			return;
		}

		SwitchToZone(zone);
	}

	/// <summary>Story / bridge entry: find a zone by ZoneName in the current scene.</summary>
	public bool TryRequestZoneByName(string zoneName)
	{
		foreach (var node in GetTree().GetNodesInGroup("camera_zones"))
		{
			if (node is not CameraZone zone)
			{
				continue;
			}

			if (zone.ZoneName == zoneName || zone.Name == zoneName)
			{
				RequestZone(zone);
				return true;
			}
		}

		return false;
	}

	private async void SwitchToZone(CameraZone zone)
	{
		_isSwitching = true;
		CurrentZoneName = zone.ZoneName;

		var halfFade = FadeDuration * 0.5f;

		var fadeOut = CreateTween();
		fadeOut.TweenProperty(_fadeRect, "color:a", 1f, halfFade);
		await ToSignal(fadeOut, Tween.SignalName.Finished);

		_activeCamera = zone.Camera;
		zone.Camera.MakeCurrent();

		var fadeIn = CreateTween();
		fadeIn.TweenProperty(_fadeRect, "color:a", 0f, halfFade);
		await ToSignal(fadeIn, Tween.SignalName.Finished);

		_isSwitching = false;
		var gameState = GetNodeOrNull<GameState>("/root/GameState");
		if (gameState != null)
		{
			gameState.CurrentZoneName = zone.ZoneName;
		}

		GD.Print($"Camera zone -> {zone.ZoneName}");
	}
}

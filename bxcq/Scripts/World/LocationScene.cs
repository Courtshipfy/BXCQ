using Godot;
using BXCQ.CameraSystem;
using BXCQ.GameInput;
using BXCQ.Player;

namespace BXCQ.World;

public partial class LocationScene : Node2D
{
	[Export] public string LocationDisplayName { get; set; } = "Location";

	private MovementInputReader _inputReader = null!;
	private PlayerController _player = null!;
	private CameraDirector _cameraDirector = null!;
	private Label _debugLabel = null!;
	private GameState _gameState = null!;

	public override void _Ready()
	{
		_inputReader = GetNode<MovementInputReader>("MovementInputReader");
		_player = GetNode<PlayerController>("Player");
		_cameraDirector = GetNode<CameraDirector>("CameraDirector");
		_debugLabel = GetNode<Label>("HudLayer/DebugLabel");
		_gameState = GetNode<GameState>("/root/GameState");

		ApplySpawn();
		_player.SnapToPathNetwork();
		_gameState.CurrentScenePath = SceneFilePath;
		GetNode<SceneTransition>("/root/SceneTransition").NotifyLocationReady();
		CallDeferred(nameof(ApplyRuntimeZone));
	}

	public override void _Process(double delta)
	{
		_gameState.CurrentZoneName = _cameraDirector.CurrentZoneName;
		_debugLabel.Text =
			$"《笔削春秋》玩法验证 | {LocationDisplayName} | Zone:{_gameState.CurrentZoneName} | " +
			$"Last:{_player.LastInteractionName} | {_inputReader.CurrentIntent.Describe()}\n" +
			"三场景 | Person · Examine · Investigate · Hotspot | Path Network + Smart Interact";
	}

	private void ApplyRuntimeZone()
	{
		if (!string.IsNullOrWhiteSpace(_gameState.CurrentZoneName))
		{
			_cameraDirector.TryRequestZoneByName(_gameState.CurrentZoneName);
		}
	}

	private void ApplySpawn()
	{
		var spawnId = _gameState.ConsumePendingSpawnId();
		var marker = GetNodeOrNull<Marker2D>($"Spawns/{spawnId}")
			?? GetNodeOrNull<Marker2D>("Spawns/default");
		if (marker != null)
		{
			_player.GlobalPosition = marker.GlobalPosition;
		}
	}
}

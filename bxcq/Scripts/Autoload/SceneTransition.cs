using Godot;

namespace BXCQ;

public partial class SceneTransition : CanvasLayer
{
	[Export] public float FadeDuration { get; set; } = 0.35f;

	private ColorRect _fadeRect = null!;
	private bool _busy;
	private bool _pendingEnterFade;

	public bool IsBusy => _busy;

	public override void _Ready()
	{
		Layer = 128;
		_fadeRect = new ColorRect
		{
			Name = "FadeRect",
			Color = new Color(0f, 0f, 0f, 0f),
			MouseFilter = Control.MouseFilterEnum.Ignore,
			AnchorRight = 1f,
			AnchorBottom = 1f,
			GrowHorizontal = Control.GrowDirection.Both,
			GrowVertical = Control.GrowDirection.Both,
		};
		AddChild(_fadeRect);
	}

	public async void GoTo(string scenePath, string spawnId = "default")
	{
		if (_busy)
		{
			return;
		}

		_busy = true;
		var gameState = GetNode<GameState>("/root/GameState");
		gameState.CaptureWorldFromTree(GetTree());
		gameState.PendingSpawnId = spawnId;
		gameState.CurrentScenePath = scenePath;
		await FadeTo(1f);
		_pendingEnterFade = true;

		var error = GetTree().ChangeSceneToFile(scenePath);
		if (error != Error.Ok)
		{
			GD.PrintErr($"Failed to change scene: {scenePath} ({error})");
			_pendingEnterFade = false;
			await FadeTo(0f);
			_busy = false;
		}
	}

	public async void NotifyLocationReady()
	{
		if (!_pendingEnterFade)
		{
			_busy = false;
			return;
		}

		_pendingEnterFade = false;
		await FadeTo(0f);
		_busy = false;
		GD.Print($"Entered scene: {GetTree().CurrentScene?.SceneFilePath}");
	}

	private async System.Threading.Tasks.Task FadeTo(float alpha)
	{
		var tween = CreateTween();
		tween.TweenProperty(_fadeRect, "color:a", alpha, FadeDuration * 0.5f);
		await ToSignal(tween, Tween.SignalName.Finished);
	}
}

using Godot;
using BXCQ.Player;

namespace BXCQ.CameraSystem;

public partial class CameraZone : Area2D
{
	[Export] public string ZoneName { get; set; } = "Zone";
	[Export] public bool IsInitialZone { get; set; }

	private Camera2D _camera = null!;
	private CameraDirector _director = null!;

	public Camera2D Camera => _camera;

	public override void _Ready()
	{
		_camera = GetNode<Camera2D>("Camera2D");
		_director = GetNode<CameraDirector>("../../CameraDirector");
		Monitoring = true;
		Monitorable = false;
		CollisionLayer = 0;
		CollisionMask = 1;
		BodyEntered += OnBodyEntered;
		AddToGroup("camera_zones");

		if (IsInitialZone)
		{
			_director.RegisterInitialCamera(_camera, ZoneName);
		}
	}

	private void OnBodyEntered(Node2D body)
	{
		if (body is not PlayerController)
		{
			return;
		}

		_director.RequestZone(this);
	}
}

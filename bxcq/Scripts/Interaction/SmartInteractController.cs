using Godot;
using BXCQ.PathSystem;
using BXCQ.Player;

namespace BXCQ.Interaction;

/// <summary>Owns Smart Interact planning, approach, arrival, cancellation, and completion.</summary>
internal sealed class SmartInteractController
{
	private readonly PlayerController _player;
	private readonly Area2D _interactionArea;
	private readonly PathNetworkMotor _motor;
	private IInteractable _pendingTarget = null!;
	private bool _hasPendingTarget;

	public SmartInteractController(
		PlayerController player,
		Area2D interactionArea,
		PathNetworkMotor motor)
	{
		_player = player;
		_interactionArea = interactionArea;
		_motor = motor;
	}

	public bool Request(IInteractable target)
	{
		var plan = target.PlanInteraction(_player);
		if (!plan.IsAvailable)
		{
			return false;
		}

		if (IsCloseEnough(target))
		{
			return Complete(target);
		}

		_pendingTarget = target;
		_hasPendingTarget = true;
		_motor.SetClickGoal(plan.ApproachPoint);
		GD.Print(
			$"Smart interact [{target.DisplayName}]: approach={plan.ApproachPoint} " +
			$"legs≈{_motor.ClickRouteLegCount} routeLen≈{_motor.RemainingRouteLength():F0}");
		return true;
	}

	public void Tick(bool hadClickRoute)
	{
		if (!_hasPendingTarget)
		{
			return;
		}

		if (IsCloseEnough(_pendingTarget))
		{
			Complete(_pendingTarget);
			return;
		}

		if (hadClickRoute && !_motor.HasClickRoute)
		{
			GD.Print("Smart interact: arrived on Path Network but still too far — cancelled");
			Cancel();
		}
	}

	public void Cancel()
	{
		_hasPendingTarget = false;
		_pendingTarget = null!;
	}

	private bool Complete(IInteractable target)
	{
		_motor.ClearClickRoute();
		Cancel();
		if (!target.TryExecuteInteraction(_player))
		{
			return false;
		}

		_player.RecordInteraction(target.DisplayName);
		return true;
	}

	private bool IsCloseEnough(IInteractable target)
	{
		if (target is Area2D area)
		{
			foreach (var overlapping in _interactionArea.GetOverlappingAreas())
			{
				if (overlapping == area)
				{
					return true;
				}
			}
		}

		if (target is not Node2D node)
		{
			return false;
		}

		var withinAxisRange =
			Mathf.Abs(node.GlobalPosition.X - _player.GlobalPosition.X) <= _player.InteractRangeX &&
			Mathf.Abs(node.GlobalPosition.Y - _player.GlobalPosition.Y) <= _player.InteractArriveDistance;
		return withinAxisRange ||
			_player.GlobalPosition.DistanceTo(node.GlobalPosition) <= _player.InteractArriveDistance;
	}
}

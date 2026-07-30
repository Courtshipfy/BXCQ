using Godot;
using BXCQ.Player;

namespace BXCQ.Interaction;

public interface IInteractable
{
	string DisplayName { get; }
	InteractionPlan PlanInteraction(PlayerController player);
	bool TryExecuteInteraction(PlayerController player);
}

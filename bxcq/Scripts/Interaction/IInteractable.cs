using Godot;
using BXCQ.Player;

namespace BXCQ.Interaction;

public interface IInteractable
{
	string DisplayName { get; }
	bool CanInteract(PlayerController player);
	void PrepareInteraction(PlayerController player);
	void Interact(PlayerController player);
	Vector2 GetInteractionPoint(PlayerController player);
}

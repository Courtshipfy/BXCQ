using Godot;
using BXCQ.Player;

namespace BXCQ.Interaction;

public interface IInteractable
{
	bool CanInteract(PlayerController player);
	void Interact(PlayerController player);
	Vector2 GetInteractionPoint(PlayerController player);
}

namespace BXCQ.PathSystem;

/// <summary>One continuous slide along a single Walk Path between two offsets.</summary>
public readonly record struct PathLeg(int PathId, float FromOffset, float ToOffset)
{
	public float Length => System.MathF.Abs(ToOffset - FromOffset);
}

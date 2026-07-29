namespace BXCQ.PathSystem;

/// <summary>Position on the Path Network: which Walk Path and offset along its baked curve.</summary>
public readonly record struct PathPose(int PathId, float Offset);

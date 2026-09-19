return {
    FacialProbeOnly = false,
    UseFaceLayer = true, -- v0.14: Convai JawOpen drives the user-verified JawOpenAlpha.
    AutoStartConvai = true,
    -- Installer writes an absolute runtime path into runtime_path.lua.
    MaxDistance = 450.0, -- Unreal units, about 4.5 metres
    CompanionMaxDistance = 10000.0, -- 100 m; native follower navigation owns movement
    TraceDistance = 1200.0,
    TraceChannel = 0, -- Visibility
    FacingHalfAngle = 80.0, -- Broad front area, prefer the character you face
    FaceAndHold = true, -- During F6 test / F7 conversation; release on stop
    DevelopmentCommands = false, -- Disabled after v0.5 crash; user performs tests
    -- Overrides are Convai ARKit channel -> exact cooked morph target name.
    MorphMap = {},
}

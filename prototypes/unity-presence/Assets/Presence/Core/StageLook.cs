using System;

namespace Neura.Presence
{
    // A colour as plain floats so the palette stays independent of Unity.
    public struct Rgb
    {
        public float R, G, B;
        public Rgb(float r, float g, float b) { R = r; G = g; B = b; }
        public bool Equals(Rgb other) { return R == other.R && G == other.G && B == other.B; }
    }

    // What the room looks like for a snapshot: background, the accent used by
    // the stage rim and lit details, and (in Her Suite) the walls.
    public struct StagePalette
    {
        public Rgb Background, Accent, Wall;

        private static readonly string[] Rooms = {
            "penthouse", "reflection_bay", "joy_lounge", "mood_den", "dream_atrium", "legacy_vault", "her_suite"
        };
        private static readonly Rgb[] RoomAccents = {
            new Rgb(0.12f, 0.73f, 0.72f), new Rgb(0.20f, 0.52f, 0.85f),
            new Rgb(0.72f, 0.43f, 0.92f), new Rgb(0.38f, 0.70f, 0.56f),
            new Rgb(0.48f, 0.43f, 0.86f), new Rgb(0.72f, 0.61f, 0.36f),
            new Rgb(1.00f, 0.79f, 0.30f)
        };
        private static readonly Rgb DefaultBackground = new Rgb(0.025f, 0.04f, 0.08f);
        private static readonly Rgb DefaultWall = new Rgb(0.07f, 0.10f, 0.17f);

        // Lighting moods. In Her Suite, standard means her own gold hour.
        public static StagePalette Evaluate(AvatarSnapshot state)
        {
            bool suite = state.RoomId == "her_suite";
            string mood = state.Lighting == "standard" && suite ? "gold" : state.Lighting;
            switch (mood)
            {
                case "gold":
                    return new StagePalette { Background = new Rgb(0.06f, 0.045f, 0.03f),
                        Accent = new Rgb(1.00f, 0.79f, 0.30f), Wall = new Rgb(0.09f, 0.07f, 0.045f) };
                case "aurora":
                    return new StagePalette { Background = new Rgb(0.02f, 0.05f, 0.07f),
                        Accent = new Rgb(0.50f, 0.90f, 1.00f), Wall = new Rgb(0.045f, 0.07f, 0.09f) };
                case "dusk":
                    return new StagePalette { Background = new Rgb(0.04f, 0.03f, 0.07f),
                        Accent = new Rgb(0.79f, 0.68f, 1.00f), Wall = new Rgb(0.07f, 0.055f, 0.10f) };
                default:
                    int index = Array.IndexOf(Rooms, state.RoomId);
                    return new StagePalette { Background = DefaultBackground,
                        Accent = RoomAccents[index < 0 ? 0 : index], Wall = DefaultWall };
            }
        }
    }

    // Where the stage camera sits, in the stage's local metres, and what it
    // looks at. Every framing keeps the whole 3 m standing area in front of it.
    public struct StageFraming
    {
        public float PositionX, PositionY, PositionZ;
        public float TargetX, TargetY, TargetZ;
        public float FieldOfView;

        public static StageFraming Evaluate(AvatarSnapshot state)
        {
            // Resting lowers her head, so the camera follows it down slightly.
            float rest = state.Resting ? 0.18f : 0f;
            switch (state.Camera)
            {
                case "wide":
                    return new StageFraming { PositionX = 0f, PositionY = 2.4f, PositionZ = -7.2f,
                        TargetX = 0f, TargetY = 1.0f - rest, TargetZ = 0f, FieldOfView = 44f };
                case "face":
                    return new StageFraming { PositionX = 0.25f, PositionY = 1.55f - rest, PositionZ = -2.2f,
                        TargetX = 0f, TargetY = 1.45f - rest, TargetZ = 0f, FieldOfView = 30f };
                default:
                    return new StageFraming { PositionX = 0.65f, PositionY = 1.7f, PositionZ = -4.8f,
                        TargetX = 0f, TargetY = 0.95f - rest, TargetZ = 0f, FieldOfView = 38f };
            }
        }
    }
}

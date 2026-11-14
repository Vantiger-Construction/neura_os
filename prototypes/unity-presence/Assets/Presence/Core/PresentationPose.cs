using System;

namespace Neura.Presence
{
    public struct PresentationPose
    {
        public float Scale;
        public float HeightMultiplier;
        public float YawDegrees;

        // Only the visual mount changes. The stage and foot anchor never move.
        public static PresentationPose Evaluate(AvatarSnapshot state, double seconds)
        {
            float scale = state.Scale == "compact" ? 0.8f : state.Scale == "large" ? 1.15f : 1f;
            float stanceYaw = state.Stance == "reflective" || state.Stance == "dreaming" ? -6f :
                state.Stance == "playful" || state.Stance == "guardian" ? 6f : 0f;
            bool moving = !state.SafeMode && state.Motion != "still" &&
                !double.IsNaN(seconds) && !double.IsInfinity(seconds);
            double wave = moving ? Math.Sin(seconds * 1.6) : 0;
            float amplitude = state.Motion == "expressive" ? 1f : 0.4f;
            if (state.Resting && !state.SafeMode)
            {
                // Settled by the window: lower and turned toward it, with only
                // slow breathing. Feet stay on the anchor; only the mount scales.
                return new PresentationPose
                {
                    Scale = scale,
                    HeightMultiplier = 0.82f + (float)wave * 0.006f,
                    YawDegrees = -28f + (float)wave * 1.5f
                };
            }
            return new PresentationPose
            {
                Scale = scale,
                HeightMultiplier = 1f + (float)wave * 0.02f * amplitude,
                YawDegrees = stanceYaw + (float)wave * 5f * amplitude
            };
        }
    }
}

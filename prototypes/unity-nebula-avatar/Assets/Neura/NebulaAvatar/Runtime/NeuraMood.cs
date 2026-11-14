using System;
using UnityEngine;

namespace Neura.Avatar
{
    /// <summary>How Neura's human is feeling. Neura mirrors this in her body.</summary>
    public enum NeuraEmotion { Calm, Joy, Love, Sad, Anxious, Frustrated }

    /// <summary>Everything that changes about Neura's look for one emotion.</summary>
    [Serializable]
    public struct NeuraMoodLook
    {
        [Tooltip("Eight colors for the nebula that flows inside her body.")]
        public Color[] nebula;
        [Tooltip("Eyes, markings, filament tips, light streams.")]
        public Color accent;
        [Tooltip("Heart light and warm highlights.")]
        public Color heart;
        [Tooltip("Speed of the inner nebula drift (1 = calm).")]
        public float driftSpeed;
        [Tooltip("Heart-light pulses per second.")]
        public float pulseRate;
        [Tooltip("Heart-light size multiplier (1 = calm).")]
        public float heartSize;
        [Tooltip("Overall brightness of her points of light.")]
        public float brightness;
        [Tooltip("How much her points twinkle, 0 to 1.")]
        public float sparkle;
        [Tooltip("Speed of her float and sway (1 = calm).")]
        public float floatSpeed;
        [Tooltip("Mouth: -1 sad, 0 neutral, 1 big smile.")]
        public float smile;
        [Tooltip("Inner brows lifted in concern, 0 to 1.")]
        public float browInnerUp;
        [Tooltip("Head tilt in degrees.")]
        public float headTiltDeg;

        public static NeuraMoodLook Lerp(NeuraMoodLook a, NeuraMoodLook b, float t)
        {
            var r = new NeuraMoodLook
            {
                nebula = new Color[8],
                accent = Color.Lerp(a.accent, b.accent, t),
                heart = Color.Lerp(a.heart, b.heart, t),
                driftSpeed = Mathf.Lerp(a.driftSpeed, b.driftSpeed, t),
                pulseRate = Mathf.Lerp(a.pulseRate, b.pulseRate, t),
                heartSize = Mathf.Lerp(a.heartSize, b.heartSize, t),
                brightness = Mathf.Lerp(a.brightness, b.brightness, t),
                sparkle = Mathf.Lerp(a.sparkle, b.sparkle, t),
                floatSpeed = Mathf.Lerp(a.floatSpeed, b.floatSpeed, t),
                smile = Mathf.Lerp(a.smile, b.smile, t),
                browInnerUp = Mathf.Lerp(a.browInnerUp, b.browInnerUp, t),
                headTiltDeg = Mathf.Lerp(a.headTiltDeg, b.headTiltDeg, t)
            };
            for (int i = 0; i < 8; i++)
            {
                var ca = a.nebula != null && a.nebula.Length > i ? a.nebula[i] : Color.black;
                var cb = b.nebula != null && b.nebula.Length > i ? b.nebula[i] : Color.black;
                r.nebula[i] = Color.Lerp(ca, cb, t);
            }
            return r;
        }
    }

    /// <summary>The six built-in looks, matching the Neura design canvas.</summary>
    public static class NeuraMoodLibrary
    {
        static Color H(string hex)
        {
            ColorUtility.TryParseHtmlString(hex, out var c);
            return c;
        }

        static Color[] P(params string[] hex)
        {
            var a = new Color[hex.Length];
            for (int i = 0; i < hex.Length; i++) a[i] = H(hex[i]);
            return a;
        }

        public static NeuraMoodLook Get(NeuraEmotion e)
        {
            switch (e)
            {
                case NeuraEmotion.Joy:
                    return new NeuraMoodLook
                    {
                        nebula = P("#B0507A", "#E08A3A", "#D0607A", "#7A3AA0", "#E0A040", "#C0408A", "#F0B050", "#D07A50"),
                        accent = H("#FFD98A"), heart = H("#FFE7A8"),
                        driftSpeed = 1.8f, pulseRate = 0.38f, heartSize = 1.33f, brightness = 1.08f, sparkle = 0.75f,
                        floatSpeed = 1.5f, smile = 1f, browInnerUp = 0.14f, headTiltDeg = -9f
                    };
                case NeuraEmotion.Love:
                    return new NeuraMoodLook
                    {
                        nebula = P("#B0407A", "#D06A8A", "#8A2A6A", "#C0508A", "#E08AA0", "#9A3A8A", "#F0A0B0", "#B0507A"),
                        accent = H("#FFB8C8"), heart = H("#FFC8D6"),
                        driftSpeed = 1.3f, pulseRate = 0.28f, heartSize = 1.26f, brightness = 1.04f, sparkle = 0.6f,
                        floatSpeed = 1.12f, smile = 0.8f, browInnerUp = 0.29f, headTiltDeg = -8f
                    };
                case NeuraEmotion.Sad:
                    return new NeuraMoodLook
                    {
                        nebula = P("#141E5A", "#1E2E70", "#22306A", "#1A2460", "#24386E", "#18205A", "#2A3A7A", "#1C2A66"),
                        accent = H("#8FA9E0"), heart = H("#B8C8F0"),
                        driftSpeed = 0.6f, pulseRate = 0.125f, heartSize = 0.76f, brightness = 0.78f, sparkle = 0.25f,
                        floatSpeed = 0.7f, smile = -0.35f, browInnerUp = 1f, headTiltDeg = -2f
                    };
                case NeuraEmotion.Anxious:
                    return new NeuraMoodLook
                    {
                        nebula = P("#4A2A9A", "#2A8AB0", "#6A2A9A", "#3A3AB0", "#2AA0C0", "#5A2AA0", "#7A3AC0", "#2A7AB0"),
                        accent = H("#B9A7FF"), heart = H("#D8CCFF"),
                        driftSpeed = 3.6f, pulseRate = 0.55f, heartSize = 0.9f, brightness = 0.95f, sparkle = 0.7f,
                        floatSpeed = 1.8f, smile = 0.1f, browInnerUp = 0.86f, headTiltDeg = -4f
                    };
                case NeuraEmotion.Frustrated:
                    return new NeuraMoodLook
                    {
                        nebula = P("#8A1E2E", "#B0401E", "#6A1A3A", "#A0301E", "#C05A1E", "#7A1E3A", "#D0702A", "#8A2A2A"),
                        accent = H("#FFA070"), heart = H("#FFC8A0"),
                        driftSpeed = 2.25f, pulseRate = 0.42f, heartSize = 1.02f, brightness = 0.95f, sparkle = 0.5f,
                        floatSpeed = 1.29f, smile = 0.05f, browInnerUp = 0.57f, headTiltDeg = -5f
                    };
                default: // Calm
                    return new NeuraMoodLook
                    {
                        nebula = P("#1F3F9A", "#0E7A86", "#2A5AA0", "#3A4A9A", "#0E7A86", "#2C5AA8", "#3A8AB0", "#2A6AB0"),
                        accent = H("#7DE3D0"), heart = H("#CFF7FF"),
                        driftSpeed = 1f, pulseRate = 0.2f, heartSize = 1f, brightness = 1f, sparkle = 0.45f,
                        floatSpeed = 1f, smile = 0.55f, browInnerUp = 0f, headTiltDeg = -6f
                    };
            }
        }
    }
}

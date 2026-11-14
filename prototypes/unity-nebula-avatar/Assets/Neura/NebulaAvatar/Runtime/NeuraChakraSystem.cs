using System;
using UnityEngine;

namespace Neura.Avatar
{
    /// <summary>
    /// Seven chakra lights up Neura's spine, joined by a flowing energy channel.
    /// Alignment (0 to 1) controls them: aligned = all bright, centered and flowing;
    /// misaligned = some dim, drift off-center, and the channel breaks into gaps.
    /// Positions come from the humanoid skeleton, so they follow her as she moves.
    /// </summary>
    [DefaultExecutionOrder(110)]
    public class NeuraChakraSystem : MonoBehaviour
    {
        public enum Chakra { Root, Sacral, SolarPlexus, Heart, Throat, ThirdEye, Crown }

        [Tooltip("Humanoid animator for bone lookup.")]
        public Animator animator;
        [Tooltip("Optional: seven transforms (root to crown) to use instead of humanoid bones.")]
        public Transform[] customAnchors = new Transform[7];

        [Range(0f, 1f)] public float alignment = 0.72f;
        /// <summary>1 = full motion, 0 = Still (Safe Mode). Set by NeuraNebulaAvatar.</summary>
        [NonSerialized] public float motion = 1f;
        float clock;

        [Header("Look")]
        public float coreSize = 0.03f;
        public float glowSize = 0.16f;
        public float ringSize = 0.12f;
        [Tooltip("How far chakras drift off-center at zero alignment, in meters.")]
        public float misalignOffset = 0.05f;
        public float channelWidth = 0.006f;
        [Tooltip("Push the lights slightly toward the viewer so they sit in front of the spine, in meters.")]
        public float forwardOffset = 0.02f;

        [Header("Materials (optional; created automatically if empty)")]
        public Material dotMaterial;
        public Material ringMaterial;
        public Material channelMaterial;

        /// <summary>Lowest-glowing chakra right now, for captions or the companion's own words.</summary>
        public Chakra Weakest { get; private set; }

        static readonly Color[] Colors =
        {
            new Color(1.00f, 0.35f, 0.35f), // root
            new Color(1.00f, 0.60f, 0.23f), // sacral
            new Color(1.00f, 0.85f, 0.29f), // solar plexus
            new Color(0.35f, 0.88f, 0.54f), // heart
            new Color(0.29f, 0.72f, 1.00f), // throat
            new Color(0.48f, 0.48f, 1.00f), // third eye
            new Color(0.78f, 0.49f, 1.00f)  // crown
        };
        // Which lights fade first as alignment drops, and which way each drifts.
        static readonly float[] Weak = { 0.10f, 0.30f, 0.15f, 0.00f, 0.25f, 0.35f, 0.20f };
        static readonly float[] Drift = { 0.82f, -0.65f, 1.00f, -0.35f, 0.70f, -0.88f, 0.53f };

        Transform[] bones = new Transform[7];
        readonly Vector3[] headLocalOffset = new Vector3[7];
        float[] upOff = { -0.07f, 0f, 0f, 0.06f, 0f, 0.07f, 0.2f };
        float[] fwdOff = { 0f, 0f, 0f, 0f, 0f, 0.09f, 0f };
        Transform head;

        ParticleSystem dotsPS, ringsPS;
        ParticleSystem.Particle[] dots = new ParticleSystem.Particle[14];
        ParticleSystem.Particle[] rings = new ParticleSystem.Particle[7];
        LineRenderer channel;
        Texture2D dashTex;
        float dashDuty = -1f, dashScroll;
        readonly Vector3[] linePts = new Vector3[7];
        bool ready;

        void Start()
        {
            if (animator == null) animator = GetComponentInParent<Animator>();
            if (!ResolveAnchors())
            {
                Debug.LogWarning("[Neura] NeuraChakraSystem needs a humanoid Animator or seven custom anchors.", this);
                enabled = false;
                return;
            }

            if (dotMaterial == null) dotMaterial = NeuraFxUtil.CreateAdditive(NeuraFxUtil.SoftDot(64, 1.8f), "Neura Chakra Glow");
            if (ringMaterial == null) ringMaterial = NeuraFxUtil.CreateAdditive(NeuraFxUtil.PetalRing(128, 12), "Neura Chakra Ring");
            dashTex = NeuraFxUtil.Dash(0.8f);
            if (channelMaterial == null) channelMaterial = NeuraFxUtil.CreateAdditive(dashTex, "Neura Channel");

            dotsPS = NeuraFxUtil.CreateManualParticleSystem(transform, "Neura Chakra Lights", 14, dotMaterial, 0.5f);
            ringsPS = NeuraFxUtil.CreateManualParticleSystem(transform, "Neura Chakra Rings", 7, ringMaterial, 0.5f);
            for (int i = 0; i < 14; i++) { dots[i].startLifetime = 1000f; dots[i].remainingLifetime = 1000f; }
            for (int i = 0; i < 7; i++) { rings[i].startLifetime = 1000f; rings[i].remainingLifetime = 1000f; }

            var go = new GameObject("Neura Energy Channel");
            go.transform.SetParent(transform, false);
            channel = go.AddComponent<LineRenderer>();
            channel.positionCount = 7;
            channel.useWorldSpace = true;
            channel.textureMode = LineTextureMode.Tile;
            channel.sharedMaterial = channelMaterial;
            channel.shadowCastingMode = UnityEngine.Rendering.ShadowCastingMode.Off;
            channel.receiveShadows = false;
            var g = new Gradient();
            var keys = new GradientColorKey[7];
            for (int i = 0; i < 7; i++) keys[i] = new GradientColorKey(Colors[i], i / 6f);
            g.SetKeys(keys, new[] { new GradientAlphaKey(1f, 0f), new GradientAlphaKey(1f, 1f) });
            channel.colorGradient = g;
            ready = true;
        }

        bool ResolveAnchors()
        {
            bool custom = customAnchors != null && customAnchors.Length == 7 && Array.TrueForAll(customAnchors, t => t != null);
            if (custom)
            {
                bones = (Transform[])customAnchors.Clone();
                upOff = new float[7]; fwdOff = new float[7];
            }
            else
            {
                if (animator == null || !animator.isHuman) return false;
                Transform B(HumanBodyBones b) => animator.GetBoneTransform(b);
                Transform Or(Transform a, Transform b) => a != null ? a : b;
                var hips = B(HumanBodyBones.Hips);
                if (hips == null) return false;
                var spine = Or(B(HumanBodyBones.Spine), hips);
                var chest = Or(B(HumanBodyBones.Chest), spine);
                var upper = B(HumanBodyBones.UpperChest);
                var neck = Or(B(HumanBodyBones.Neck), chest);
                head = Or(B(HumanBodyBones.Head), neck);
                if (upper != null) upOff[3] = 0f;
                bones = new[] { hips, spine, chest, Or(upper, chest), neck, head, head };
            }
            var root = animator != null ? animator.transform : transform;
            if (head != null)
            {
                // Store the third-eye and crown offsets in the head's own space, measured in the rest pose.
                for (int i = 5; i < 7; i++)
                    headLocalOffset[i] = Quaternion.Inverse(head.rotation) * (root.up * upOff[i] + root.forward * fwdOff[i]);
            }
            return true;
        }

        void LateUpdate()
        {
            if (!ready) return;
            var root = animator != null ? animator.transform : transform;
            float mo = Mathf.Clamp01(motion);
            clock += Time.deltaTime * mo;
            float t = clock, al = Mathf.Clamp01(alignment);
            float weakest = 2f;

            for (int i = 0; i < 7; i++)
            {
                var bone = bones[i];
                // Third eye and crown ride with the head; the rest follow the body's facing.
                Vector3 offset = (i >= 5 && head != null)
                    ? head.rotation * headLocalOffset[i]
                    : root.up * upOff[i] + root.forward * fwdOff[i];
                Vector3 p = bone.position + offset + root.forward * forwardOffset;
                p += root.right * (Drift[i] * misalignOffset * (1f - al));
                linePts[i] = p;

                float b = Mathf.Clamp(al + 0.3f - Weak[i] * 1.2f, 0.15f, 1f);
                if (b < weakest) { weakest = b; Weakest = (Chakra)i; }
                float beat = 1f + 0.15f * Mathf.Sin(t * Mathf.PI * 2f * (0.2f + 0.25f * al) + i * 0.9f);
                Color c = Colors[i];

                // glow
                dots[i].position = p;
                dots[i].startSize = glowSize * (0.6f + 0.6f * b) * beat;
                var cg = c; cg.a = 0.18f + 0.45f * b;
                dots[i].startColor = cg;
                // core
                dots[i + 7].position = p;
                dots[i + 7].startSize = coreSize * (0.6f + 0.7f * b);
                var cc = Color.Lerp(c, Color.white, 0.55f); cc.a = 0.3f + 0.7f * b;
                dots[i + 7].startColor = cc;
                // petal ring, turning faster when aligned
                rings[i].position = p;
                rings[i].startSize = ringSize * (0.6f + 0.5f * b);
                rings[i].rotation = t * (8f + 28f * al) * (i % 2 == 0 ? 1f : -1f);
                var cr = c; cr.a = 0.25f + 0.65f * b;
                rings[i].startColor = cr;
            }
            dotsPS.SetParticles(dots, 14);
            ringsPS.SetParticles(rings, 7);

            // Energy channel: solid and flowing when aligned, broken up when not.
            channel.SetPositions(linePts);
            channel.widthMultiplier = channelWidth * (0.6f + 0.6f * al);
            float duty = Mathf.Round(Mathf.Lerp(0.3f, 0.95f, al) * 20f) / 20f;
            if (!Mathf.Approximately(duty, dashDuty))
            {
                dashDuty = duty;
                NeuraFxUtil.Dash(duty, dashTex);
            }
            dashScroll -= Time.deltaTime * mo * (0.4f + 1.6f * al);
            channelMaterial.mainTextureOffset = new Vector2(dashScroll, 0f);
            channelMaterial.mainTextureScale = new Vector2(6f, 1f);
            var grad = channel.colorGradient;
            var ak = grad.alphaKeys;
            for (int k = 0; k < ak.Length; k++) ak[k].alpha = 0.3f + 0.7f * al;
            grad.alphaKeys = ak;
            channel.colorGradient = grad;
        }
    }
}

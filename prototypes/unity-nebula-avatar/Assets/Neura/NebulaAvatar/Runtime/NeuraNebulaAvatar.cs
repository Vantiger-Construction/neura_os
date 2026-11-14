using System;
using UnityEngine;

namespace Neura.Avatar
{
    /// <summary>
    /// Neura's nebula-form controller. Set her human's emotion and her alignment through the typed
    /// methods below and she blends smoothly into the new look: nebula colors, heart light, sparkle,
    /// float, face and chakras.
    ///
    /// Safe Mode follows the presence prototype's rules: she starts Still, goes Still when the app
    /// loses focus or pauses, and only moves again after an explicit SetSafeMode(false).
    /// This component has no network, audio, microphone or file access, and parses no input itself.
    /// </summary>
    [DefaultExecutionOrder(50)]
    public class NeuraNebulaAvatar : MonoBehaviour
    {
        [Header("State")]
        public NeuraEmotion emotion = NeuraEmotion.Calm;
        [Range(0f, 1f)] public float alignment = 0.72f;
        [Tooltip("Seconds to blend from one emotion to the next.")]
        public float transitionSeconds = 1.6f;

        [Header("Safe Mode (Still)")]
        [Tooltip("Start Still; motion begins only after an explicit SetSafeMode(false).")]
        public bool startInSafeMode = true;
        [Tooltip("Go Still when the app loses focus or pauses.")]
        public bool stillOnFocusLoss = true;

        [Header("Parts")]
        public NeuraPointCloudBody body;
        public NeuraChakraSystem chakras;

        [Header("Floating motion (applied to the visual model, not the NavMesh agent)")]
        [Tooltip("The model's transform under your agent. Float, sway and breathing move this.")]
        public Transform visualRoot;
        public float floatHeight = 0.04f;
        public float swayAmount = 0.025f;
        [Range(0f, 0.05f)] public float breathAmount = 0.012f;

        [Header("Heart light (optional point light at her chest)")]
        public Light heartLight;
        public float heartIntensity = 1.2f;

        [Header("Face (optional blendshapes on the source mesh)")]
        public SkinnedMeshRenderer face;
        public string smileShape = "";
        public string frownShape = "";
        public string browInnerUpShape = "";
        [Tooltip("Head bone for the mood's gentle head tilt. Leave empty to skip.")]
        public Transform headBone;
        public float tiltSign = 1f;

        /// <summary>The blended look being shown right now.</summary>
        public NeuraMoodLook CurrentLook => current;

        /// <summary>True while Neura is held Still.</summary>
        public bool SafeMode => safeMode;

        /// <summary>Raised when the target emotion changes (for UI captions, etc.).</summary>
        public event Action<NeuraEmotion> EmotionChanged;

        NeuraMoodLook from, target, current;
        NeuraEmotion shown;
        float blend = 1f, shownAlignment, alignVel, clock;
        bool safeMode;
        Vector3 baseLocalPos, baseLocalScale;
        int smileIdx = -1, frownIdx = -1, browIdx = -1;

        void Awake()
        {
            if (body == null) body = GetComponentInChildren<NeuraPointCloudBody>();
            if (chakras == null) chakras = GetComponentInChildren<NeuraChakraSystem>();
            if (visualRoot == null) visualRoot = transform;
            baseLocalPos = visualRoot.localPosition;
            baseLocalScale = visualRoot.localScale;

            shown = emotion;
            from = target = current = NeuraMoodLibrary.Get(emotion);
            shownAlignment = alignment;
            safeMode = startInSafeMode;

            if (face != null && face.sharedMesh != null)
            {
                var mesh = face.sharedMesh;
                if (!string.IsNullOrEmpty(smileShape)) smileIdx = mesh.GetBlendShapeIndex(smileShape);
                if (!string.IsNullOrEmpty(frownShape)) frownIdx = mesh.GetBlendShapeIndex(frownShape);
                if (!string.IsNullOrEmpty(browInnerUpShape)) browIdx = mesh.GetBlendShapeIndex(browInnerUpShape);
            }
        }

        // ---------- Public API ----------

        public void SetEmotion(NeuraEmotion e)
        {
            if (e == shown && blend >= 1f) return;
            emotion = e;
            from = current;
            target = NeuraMoodLibrary.Get(e);
            shown = e;
            blend = 0f;
            EmotionChanged?.Invoke(e);
        }

        public void SetAlignment(float value01) => alignment = Mathf.Clamp01(value01);

        /// <summary>Safe Mode holds her Still. Releasing it is always an explicit call.</summary>
        public void SetSafeMode(bool on)
        {
            safeMode = on;
            if (on) ResetPose();
        }

        // ---------- Lifecycle: go Still on focus loss or pause ----------

        void OnApplicationFocus(bool hasFocus)
        {
            if (!hasFocus && stillOnFocusLoss) SetSafeMode(true);
        }

        void OnApplicationPause(bool paused)
        {
            if (paused && stillOnFocusLoss) SetSafeMode(true);
        }

        // ---------- Frame loop ----------

        void Update()
        {
            if (emotion != shown) SetEmotion(emotion); // Inspector edits

            if (blend < 1f)
            {
                blend = Mathf.Min(1f, blend + Time.deltaTime / Mathf.Max(0.01f, transitionSeconds));
                float s = blend * blend * (3f - 2f * blend);
                current = NeuraMoodLook.Lerp(from, target, s);
            }
            shownAlignment = Mathf.SmoothDamp(shownAlignment, alignment, ref alignVel, transitionSeconds * 0.6f);

            float motion = safeMode ? 0f : 1f;
            if (body != null) { body.look = current; body.motion = motion; }
            if (chakras != null) { chakras.alignment = shownAlignment; chakras.motion = motion; }

            if (!safeMode)
            {
                // Float, sway and breathe, at the mood's pace.
                clock += Time.deltaTime;
                float t = clock * current.floatSpeed;
                visualRoot.localPosition = baseLocalPos
                    + Vector3.up * (Mathf.Sin(t * Mathf.PI * 2f / 9f) * floatHeight)
                    + Vector3.right * (Mathf.Sin(t * Mathf.PI * 2f / 16f) * swayAmount);
                visualRoot.localScale = baseLocalScale * (1f + breathAmount * Mathf.Sin(clock * Mathf.PI * 2f / 6f));
            }

            if (heartLight != null)
            {
                float beat = safeMode ? 1f : 0.75f + 0.25f * Mathf.Sin(clock * Mathf.PI * 2f * current.pulseRate);
                heartLight.color = current.heart;
                heartLight.intensity = heartIntensity * current.heartSize * beat * current.brightness;
            }

            if (face != null)
            {
                if (smileIdx >= 0) face.SetBlendShapeWeight(smileIdx, Mathf.Max(0f, current.smile) * 100f);
                if (frownIdx >= 0) face.SetBlendShapeWeight(frownIdx, Mathf.Max(0f, -current.smile) * 100f);
                if (browIdx >= 0) face.SetBlendShapeWeight(browIdx, current.browInnerUp * 100f);
            }
        }

        void LateUpdate()
        {
            // Additive head tilt on top of whatever animation is playing (a pose, not motion).
            if (headBone != null)
            {
                var axis = visualRoot != null ? visualRoot.forward : transform.forward;
                headBone.rotation = Quaternion.AngleAxis(current.headTiltDeg * tiltSign, axis) * headBone.rotation;
            }
        }

        void ResetPose()
        {
            if (visualRoot == null) return;
            visualRoot.localPosition = baseLocalPos;
            visualRoot.localScale = baseLocalScale;
        }

        void OnDisable()
        {
            safeMode = true;
            ResetPose();
        }
    }
}

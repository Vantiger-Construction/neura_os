using System.Collections.Generic;
using UnityEngine;

namespace Neura.Presence
{
    // Standalone synthetic harness. This is not a live app bridge or an IPC host.
    public sealed class PresencePrototype : MonoBehaviour
    {
        private static readonly string[] Rooms = {
            "penthouse", "reflection_bay", "joy_lounge", "mood_den", "dream_atrium", "legacy_vault"
        };
        private static readonly string[] Stances = {
            "welcoming", "reflective", "playful", "grounding", "dreaming", "guardian"
        };
        private static readonly string[] Motions = { "still", "subtle", "expressive" };
        private static readonly string[] Scales = { "compact", "standard", "large" };
        private static readonly string[] Phases = { "idle", "thinking", "speaking", "listening", "safeMode" };
        private static readonly Color[] RoomColors = {
            new Color(0.12f, 0.73f, 0.72f), new Color(0.20f, 0.52f, 0.85f),
            new Color(0.72f, 0.43f, 0.92f), new Color(0.38f, 0.70f, 0.56f),
            new Color(0.48f, 0.43f, 0.86f), new Color(0.72f, 0.61f, 0.36f)
        };

        private readonly PresentationSession session = new PresentationSession();
        private readonly List<Material> ownedMaterials = new List<Material>();
        private Material rimMaterial, phaseMaterial;
        private GameObject generatedRoot;
        private bool hasFocus = true, paused;
        private int roomIndex, motionIndex = 1, scaleIndex = 1, phaseIndex;
        private float elapsed;
        private string draft;
        private Vector2 scroll;

        public Transform StageAnchor { get; private set; }
        public Transform VisualMount { get; private set; }
        public AvatarSnapshot Current { get { return session.Current; } }
        public SnapshotError LastError { get { return session.LastError; } }

        private void Awake()
        {
            BuildStage();
            draft = SyntheticJson();
            RenderSnapshot();
        }

        private void OnEnable() { SuspendPresentation(); }
        private void OnDisable() { SuspendPresentation(); }
        private void OnApplicationFocus(bool value)
        {
            hasFocus = value;
            SuspendPresentation();
        }
        private void OnApplicationPause(bool value)
        {
            paused = value;
            SuspendPresentation();
        }

        public void SuspendPresentation()
        {
            session.Reset();
            elapsed = 0;
            RenderSnapshot();
        }

        public void SetLocalSafeMode(bool value)
        {
            session.SetLocalSafeMode(value);
            elapsed = 0;
            RenderSnapshot();
        }

        // Call only on Unity's main thread. No listener, polling, file input or queue.
        public bool ApplySyntheticSnapshot(string json)
        {
            if (!isActiveAndEnabled || !hasFocus || paused)
            {
                SuspendPresentation();
                return false;
            }
            bool valid = session.Accept(json);
            elapsed = 0;
            RenderSnapshot(); // Safe Mode takes effect before the next frame.
            return valid;
        }

        private void Update()
        {
            if (hasFocus && !paused && !Current.SafeMode && Current.Motion != "still")
                elapsed = (elapsed + Time.unscaledDeltaTime) % (Mathf.PI * 2f / 1.6f);
            RenderPose();
        }

        private void RenderSnapshot()
        {
            if (VisualMount == null) return;
            int index = System.Array.IndexOf(Rooms, Current.RoomId);
            rimMaterial.color = RoomColors[index < 0 ? 0 : index];
            phaseMaterial.color = Current.SafeMode ? new Color(1f, 0.67f, 0.28f) :
                Current.Phase == "idle" ? new Color(0.5f, 0.95f, 0.8f) : new Color(0.7f, 0.7f, 1f);
            RenderPose();
        }

        private void RenderPose()
        {
            if (VisualMount == null) return;
            var pose = PresentationPose.Evaluate(Current, elapsed);
            VisualMount.localPosition = Vector3.zero;
            VisualMount.localRotation = Quaternion.Euler(0, pose.YawDegrees, 0);
            VisualMount.localScale = new Vector3(pose.Scale, pose.Scale * pose.HeightMultiplier, pose.Scale);
        }

        private void BuildStage()
        {
            generatedRoot = new GameObject("Synthetic presence stage");
            generatedRoot.transform.SetParent(transform, false);
            var deck = MakeMaterial(new Color(0.07f, 0.10f, 0.17f));
            var body = MakeMaterial(new Color(0.60f, 0.83f, 0.90f));
            var face = MakeMaterial(new Color(0.10f, 0.20f, 0.28f));
            var eyes = MakeMaterial(new Color(0.44f, 1f, 0.9f));
            rimMaterial = MakeMaterial(RoomColors[0]);
            phaseMaterial = MakeMaterial(new Color(1f, 0.67f, 0.28f));
            Part("Defined standing area (3m diameter)", PrimitiveType.Cylinder, generatedRoot.transform,
                Vector3.zero, new Vector3(3f, 0.04f, 3f), rimMaterial);
            Part("Stage deck", PrimitiveType.Cylinder, generatedRoot.transform,
                new Vector3(0, 0.04f, 0), new Vector3(2.85f, 0.02f, 2.85f), deck);
            StageAnchor = new GameObject("Standing anchor (feet at deck)").transform;
            StageAnchor.SetParent(generatedRoot.transform, false);
            StageAnchor.localPosition = new Vector3(0, 0.06f, 0);
            VisualMount = new GameObject("Visual mount - passive mesh replacement seam").transform;
            VisualMount.SetParent(StageAnchor, false);
            var placeholder = new GameObject("Placeholder companion - not approved production avatar").transform;
            placeholder.SetParent(VisualMount, false);
            Part("Body", PrimitiveType.Capsule, placeholder, new Vector3(0, 0.88f, 0),
                new Vector3(0.62f, 0.64f, 0.42f), body);
            Part("Head", PrimitiveType.Sphere, placeholder, new Vector3(0, 1.6f, 0),
                new Vector3(0.64f, 0.6f, 0.5f), body);
            Part("Face", PrimitiveType.Cube, placeholder, new Vector3(0, 1.62f, -0.22f),
                new Vector3(0.44f, 0.25f, 0.06f), face);
            foreach (float x in new[] { -0.12f, 0.12f })
            {
                Part("Eye", PrimitiveType.Sphere, placeholder, new Vector3(x, 1.64f, -0.27f),
                    new Vector3(0.065f, 0.08f, 0.035f), eyes);
                Part("Foot", PrimitiveType.Cube, placeholder, new Vector3(x * 1.5f, 0.09f, -0.04f),
                    new Vector3(0.23f, 0.18f, 0.4f), face);
                Part("Leg", PrimitiveType.Capsule, placeholder, new Vector3(x * 1.5f, 0.29f, 0),
                    new Vector3(0.16f, 0.2f, 0.18f), body);
                Part("Arm", PrimitiveType.Capsule, placeholder, new Vector3(x * 3.5f, 0.91f, 0),
                    new Vector3(0.16f, 0.33f, 0.16f), body);
            }
            Part("Synthetic phase indicator", PrimitiveType.Sphere, placeholder, new Vector3(0, 1.03f, -0.23f),
                new Vector3(0.13f, 0.13f, 0.06f), phaseMaterial);

            var cameraObject = new GameObject("Prototype camera - no audio listener");
            cameraObject.transform.SetParent(generatedRoot.transform, false);
            cameraObject.transform.localPosition = new Vector3(0.65f, 1.7f, -4.8f);
            cameraObject.transform.localRotation = Quaternion.LookRotation(
                new Vector3(0, 0.95f, 0) - cameraObject.transform.localPosition);
            var camera = cameraObject.AddComponent<Camera>();
            camera.clearFlags = CameraClearFlags.SolidColor;
            camera.backgroundColor = new Color(0.025f, 0.04f, 0.08f);
            camera.fieldOfView = 38;
            camera.nearClipPlane = 0.1f;
            camera.farClipPlane = 20;
            camera.rect = new Rect(0.36f, 0, 0.64f, 1);
        }

        private Material MakeMaterial(Color color)
        {
            var shader = Resources.Load<Shader>("NeuraPresence");
            if (shader == null) throw new System.InvalidOperationException("Missing prototype shader asset.");
            var material = new Material(shader) { color = color };
            ownedMaterials.Add(material);
            return material;
        }

        private static void Part(string name, PrimitiveType type, Transform parent,
            Vector3 position, Vector3 scale, Material material)
        {
            var part = GameObject.CreatePrimitive(type);
            part.name = name;
            part.transform.SetParent(parent, false);
            part.transform.localPosition = position;
            part.transform.localScale = scale;
            part.GetComponent<Renderer>().sharedMaterial = material;
            var collider = part.GetComponent<Collider>();
            if (collider != null)
            {
                collider.enabled = false;
                if (Application.isPlaying) Destroy(collider);
                else DestroyImmediate(collider);
            }
        }

        private string SyntheticJson()
        {
            return "{\"v\":1,\"room_id\":\"" + Rooms[roomIndex] + "\",\"phase\":\"" +
                Phases[phaseIndex] + "\",\"stance\":\"" + Stances[roomIndex] +
                "\",\"motion\":\"" + Motions[motionIndex] + "\",\"scale\":\"" +
                Scales[scaleIndex] + "\",\"safe_mode\":" + (phaseIndex == 4 ? "true" : "false") + "}";
        }

        private void OnGUI()
        {
            GUILayout.BeginArea(new Rect(12, 12, Mathf.Max(220, Screen.width * 0.34f - 24), Screen.height - 24), GUI.skin.box);
            scroll = GUILayout.BeginScrollView(scroll);
            GUILayout.Label("NEURA / PRESENCE PROTOTYPE");
            GUILayout.Label("Placeholder stage. Every input is synthetic.");
            GUILayout.Label("Microphone and audio: OFF. No app connection.");
            bool safe = GUILayout.Toggle(session.LocalSafeMode, "Local Safe Mode override");
            if (safe != session.LocalSafeMode) SetLocalSafeMode(safe);
            GUILayout.Label("Room");
            roomIndex = GUILayout.SelectionGrid(roomIndex, Rooms, 1);
            GUILayout.Label("Motion");
            motionIndex = GUILayout.SelectionGrid(motionIndex, Motions, 3);
            GUILayout.Label("Scale");
            scaleIndex = GUILayout.SelectionGrid(scaleIndex, Scales, 3);
            GUILayout.Label("Phase (display only)");
            phaseIndex = GUILayout.SelectionGrid(phaseIndex, Phases, 2);
            if (GUILayout.Button("Apply synthetic selection"))
            {
                draft = SyntheticJson();
                ApplySyntheticSnapshot(draft);
            }
            GUILayout.Label("Synthetic v1 JSON (max 512 characters)");
            draft = GUILayout.TextArea(draft ?? "", AvatarSnapshot.MaxJsonCharacters, GUILayout.MinHeight(90));
            if (GUILayout.Button("Validate and apply JSON")) ApplySyntheticSnapshot(draft);
            if (GUILayout.Button("Reset to safe Still")) SuspendPresentation();
            GUILayout.Label("Current: " + Current.RoomId + " / " + Current.Phase + " / " + Current.Stance);
            GUILayout.Label("Motion: " + Current.Motion + " / scale: " + Current.Scale);
            GUILayout.Label("Validation: " + session.LastError);
            GUILayout.Label("After backgrounding or releasing Safe Mode, apply a fresh state.");
            GUILayout.EndScrollView();
            GUILayout.EndArea();
        }

        private void OnDestroy()
        {
            if (generatedRoot != null)
                if (Application.isPlaying) Destroy(generatedRoot); else DestroyImmediate(generatedRoot);
            foreach (var material in ownedMaterials)
                if (Application.isPlaying) Destroy(material); else DestroyImmediate(material);
            ownedMaterials.Clear();
        }
    }
}

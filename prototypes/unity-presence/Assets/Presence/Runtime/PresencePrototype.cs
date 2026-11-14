using System.Collections.Generic;
using UnityEngine;

namespace Neura.Presence
{
    // Standalone presence harness. It hosts no listener or IPC; live input arrives
    // only through the separate, opt-in Bridge assembly calling ApplyLiveSnapshot.
    public sealed class PresencePrototype : MonoBehaviour
    {
        private static readonly string[] Rooms = {
            "penthouse", "reflection_bay", "joy_lounge", "mood_den", "dream_atrium", "legacy_vault", "her_suite"
        };
        private static readonly string[] Stances = {
            "welcoming", "reflective", "playful", "grounding", "dreaming", "guardian", "welcoming"
        };
        private static readonly string[] Motions = { "still", "subtle", "expressive" };
        private static readonly string[] Scales = { "compact", "standard", "large" };
        private static readonly string[] Phases = { "idle", "thinking", "speaking", "listening", "safeMode" };
        private static readonly string[] Lightings = { "standard", "gold", "aurora", "dusk" };
        private static readonly string[] Cameras = { "follow", "wide", "face" };
        private static readonly string[] Activities = { "present", "resting" };

        private readonly PresentationSession session = new PresentationSession();
        private readonly List<Material> ownedMaterials = new List<Material>();
        private Material rimMaterial, phaseMaterial, wallMaterial;
        private GameObject generatedRoot, suiteSet;
        private Camera stageCamera;
        private bool hasFocus = true, paused;
        private int roomIndex, motionIndex = 1, scaleIndex = 1, phaseIndex;
        private int lightingIndex, cameraIndex, activityIndex;
        private float elapsed;
        private string draft;
        private Vector2 scroll;

        public Transform StageAnchor { get; private set; }
        public Transform VisualMount { get; private set; }
        public AvatarSnapshot Current { get { return session.Current; } }
        public SnapshotError LastError { get { return session.LastError; } }
        // Her Suite's set (walls, window, shelf, sofa) shows only in her_suite.
        public bool SuiteVisible { get { return suiteSet != null && suiteSet.activeSelf; } }
        public Camera StageCamera { get { return stageCamera; } }

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
            SnapCamera(); // Back to the safe default framing at once.
        }

        public void SetLocalSafeMode(bool value)
        {
            session.SetLocalSafeMode(value);
            elapsed = 0;
            RenderSnapshot();
        }

        // Call only on Unity's main thread. No listener, polling, file input or queue.
        public bool ApplySyntheticSnapshot(string json) { return ApplySnapshot(json); }

        // Entry point for the opt-in, launcher-authorized relay bridge
        // (Assets/Presence/Bridge). Same guards as synthetic input: main
        // thread only, refused while unfocused or paused, strictly validated.
        public bool ApplyLiveSnapshot(string json) { return ApplySnapshot(json); }

        private bool ApplySnapshot(string json)
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
            // The camera eases toward its framing; it is not avatar motion, so
            // it settles even when motion is Still.
            MoveCamera(1f - Mathf.Exp(-6f * Time.unscaledDeltaTime));
        }

        private void RenderSnapshot()
        {
            if (VisualMount == null) return;
            var palette = StagePalette.Evaluate(Current);
            rimMaterial.color = ToColor(palette.Accent);
            wallMaterial.color = ToColor(palette.Wall);
            if (stageCamera != null) stageCamera.backgroundColor = ToColor(palette.Background);
            if (suiteSet != null) suiteSet.SetActive(Current.RoomId == "her_suite");
            phaseMaterial.color = Current.SafeMode ? new Color(1f, 0.67f, 0.28f) :
                Current.Resting ? new Color(0.55f, 0.6f, 0.85f) :
                Current.Phase == "idle" ? new Color(0.5f, 0.95f, 0.8f) : new Color(0.7f, 0.7f, 1f);
            RenderPose();
        }

        private void SnapCamera() { MoveCamera(1f); }

        private void MoveCamera(float blend)
        {
            if (stageCamera == null) return;
            var framing = StageFraming.Evaluate(Current);
            var cameraTransform = stageCamera.transform;
            var position = new Vector3(framing.PositionX, framing.PositionY, framing.PositionZ);
            var target = new Vector3(framing.TargetX, framing.TargetY, framing.TargetZ);
            cameraTransform.localPosition = Vector3.Lerp(cameraTransform.localPosition, position, blend);
            cameraTransform.localRotation = Quaternion.LookRotation(target - cameraTransform.localPosition);
            stageCamera.fieldOfView = Mathf.Lerp(stageCamera.fieldOfView, framing.FieldOfView, blend);
        }

        private static Color ToColor(Rgb rgb) { return new Color(rgb.R, rgb.G, rgb.B); }

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
            rimMaterial = MakeMaterial(ToColor(StagePalette.Evaluate(AvatarSnapshot.SafeDefault()).Accent));
            wallMaterial = MakeMaterial(new Color(0.07f, 0.10f, 0.17f));
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
            stageCamera = camera;
            BuildSuite();
        }

        // Her Suite: her own room, built from the same disabled-collider
        // primitives as the stage. Placeholder set dressing, not final art.
        // The standing area stays clear; everything sits beyond its 1.5 m radius.
        private void BuildSuite()
        {
            suiteSet = new GameObject("Her Suite set - placeholder dressing");
            suiteSet.transform.SetParent(generatedRoot.transform, false);
            var root = suiteSet.transform;
            var glass = MakeMaterial(new Color(0.03f, 0.05f, 0.10f));
            var skyline = MakeMaterial(new Color(0.06f, 0.09f, 0.16f));
            var frame = MakeMaterial(new Color(0.16f, 0.13f, 0.09f));
            var fabric = MakeMaterial(new Color(0.12f, 0.10f, 0.13f));
            var wood = MakeMaterial(new Color(0.23f, 0.18f, 0.11f));
            var leaf = MakeMaterial(new Color(0.24f, 0.36f, 0.23f));

            Part("Back wall", PrimitiveType.Cube, root, new Vector3(0, 2.25f, 3.6f), new Vector3(9f, 4.5f, 0.1f), wallMaterial);
            Part("Left wall", PrimitiveType.Cube, root, new Vector3(-4.5f, 2.25f, 1.2f), new Vector3(0.1f, 4.5f, 4.8f), wallMaterial);
            Part("Right wall", PrimitiveType.Cube, root, new Vector3(4.5f, 2.25f, 1.2f), new Vector3(0.1f, 4.5f, 4.8f), wallMaterial);

            // Window onto the night city, behind and to the right of her.
            Part("Window glass", PrimitiveType.Cube, root, new Vector3(1.2f, 2.1f, 3.52f), new Vector3(3.4f, 2.4f, 0.04f), glass);
            foreach (float x in new[] { -0.5f, 1.2f, 2.9f })
                Part("Window mullion", PrimitiveType.Cube, root, new Vector3(x, 2.1f, 3.48f), new Vector3(0.08f, 2.5f, 0.06f), frame);
            foreach (float y in new[] { 0.88f, 3.32f })
                Part("Window rail", PrimitiveType.Cube, root, new Vector3(1.2f, y, 3.48f), new Vector3(3.5f, 0.08f, 0.06f), frame);
            float[,] towers = { { -0.2f, 0.7f }, { 0.25f, 1.1f }, { 0.8f, 0.6f }, { 1.5f, 1.3f }, { 2.1f, 0.8f }, { 2.6f, 1.0f } };
            for (int i = 0; i < towers.GetLength(0); i++)
            {
                float x = towers[i, 0], height = towers[i, 1];
                Part("Skyline tower", PrimitiveType.Cube, root, new Vector3(x, 0.92f + height / 2f, 3.5f),
                    new Vector3(0.38f, height, 0.02f), skyline);
                Part("Lit window", PrimitiveType.Cube, root, new Vector3(x + 0.06f, 0.92f + height * 0.7f, 3.48f),
                    new Vector3(0.05f, 0.05f, 0.01f), rimMaterial);
            }

            // Her shelf of keepsakes on the left.
            Part("Shelf", PrimitiveType.Cube, root, new Vector3(-3.0f, 1.7f, 3.3f), new Vector3(1.8f, 0.06f, 0.4f), wood);
            Part("Keepsake box", PrimitiveType.Cube, root, new Vector3(-3.6f, 1.85f, 3.3f), new Vector3(0.22f, 0.24f, 0.22f), frame);
            Part("Keepsake book", PrimitiveType.Cube, root, new Vector3(-3.25f, 1.9f, 3.3f), new Vector3(0.08f, 0.34f, 0.24f), fabric);
            Part("Keepsake light", PrimitiveType.Sphere, root, new Vector3(-2.8f, 1.86f, 3.3f), new Vector3(0.24f, 0.24f, 0.24f), rimMaterial);
            Part("Keepsake frame", PrimitiveType.Cube, root, new Vector3(-2.35f, 1.88f, 3.32f), new Vector3(0.36f, 0.28f, 0.04f), frame);

            // A sofa to sit together on, and a plant.
            Part("Sofa seat", PrimitiveType.Cube, root, new Vector3(-2.7f, 0.25f, 1.2f), new Vector3(1.0f, 0.45f, 2.0f), fabric);
            Part("Sofa back", PrimitiveType.Cube, root, new Vector3(-3.15f, 0.7f, 1.2f), new Vector3(0.2f, 0.7f, 2.0f), fabric);
            Part("Plant pot", PrimitiveType.Cylinder, root, new Vector3(3.6f, 0.25f, 3.0f), new Vector3(0.4f, 0.25f, 0.4f), wood);
            foreach (var leafPosition in new[] { new Vector3(3.6f, 0.75f, 3.0f), new Vector3(3.45f, 0.95f, 2.9f), new Vector3(3.75f, 1.05f, 3.1f) })
                Part("Plant leaves", PrimitiveType.Sphere, root, leafPosition, new Vector3(0.45f, 0.4f, 0.45f), leaf);
            suiteSet.SetActive(false);
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
            return "{\"v\":2,\"room_id\":\"" + Rooms[roomIndex] + "\",\"phase\":\"" +
                Phases[phaseIndex] + "\",\"stance\":\"" + Stances[roomIndex] +
                "\",\"motion\":\"" + Motions[motionIndex] + "\",\"scale\":\"" +
                Scales[scaleIndex] + "\",\"safe_mode\":" + (phaseIndex == 4 ? "true" : "false") +
                ",\"lighting\":\"" + Lightings[lightingIndex] + "\",\"camera\":\"" + Cameras[cameraIndex] +
                "\",\"activity\":\"" + Activities[activityIndex] + "\"}";
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
            GUILayout.Label("Lighting (Her Suite moods)");
            lightingIndex = GUILayout.SelectionGrid(lightingIndex, Lightings, 2);
            GUILayout.Label("Camera");
            cameraIndex = GUILayout.SelectionGrid(cameraIndex, Cameras, 3);
            GUILayout.Label("Activity");
            activityIndex = GUILayout.SelectionGrid(activityIndex, Activities, 2);
            if (GUILayout.Button("Apply synthetic selection"))
            {
                draft = SyntheticJson();
                ApplySyntheticSnapshot(draft);
            }
            GUILayout.Label("Synthetic v1 or v2 JSON (max 512 characters)");
            draft = GUILayout.TextArea(draft ?? "", AvatarSnapshot.MaxJsonCharacters, GUILayout.MinHeight(90));
            if (GUILayout.Button("Validate and apply JSON")) ApplySyntheticSnapshot(draft);
            if (GUILayout.Button("Reset to safe Still")) SuspendPresentation();
            GUILayout.Label("Current: " + Current.RoomId + " / " + Current.Phase + " / " + Current.Stance);
            GUILayout.Label("Motion: " + Current.Motion + " / scale: " + Current.Scale);
            GUILayout.Label("Stage: " + Current.Lighting + " / " + Current.Camera + " / " + Current.Activity +
                " (v" + Current.SourceVersion + ")");
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

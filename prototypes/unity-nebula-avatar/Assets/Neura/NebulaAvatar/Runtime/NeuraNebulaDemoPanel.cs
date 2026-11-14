using UnityEngine;

namespace Neura.Avatar
{
    /// <summary>
    /// Test panel for Play mode: Safe Mode toggle, emotion buttons and an alignment slider,
    /// like the design canvas. Synthetic, manual input only. Remove it once the app drives Neura.
    /// </summary>
    public class NeuraNebulaDemoPanel : MonoBehaviour
    {
        public NeuraNebulaAvatar avatar;
        public bool showPanel = true;

        void Awake()
        {
            if (avatar == null) avatar = FindAnyObjectByType<NeuraNebulaAvatar>();
        }

        void OnGUI()
        {
            if (!showPanel || avatar == null) return;
            GUILayout.BeginArea(new Rect(16, 16, 300, 360), GUI.skin.box);
            bool still = GUILayout.Toggle(avatar.SafeMode, " Safe Mode (Still)");
            if (still != avatar.SafeMode) avatar.SetSafeMode(still);
            GUILayout.Space(6);
            GUILayout.Label("Her human feels:");
            foreach (NeuraEmotion e in System.Enum.GetValues(typeof(NeuraEmotion)))
            {
                string label = (avatar.emotion == e ? "> " : "  ") + e;
                if (GUILayout.Button(label)) avatar.SetEmotion(e);
            }
            GUILayout.Space(8);
            GUILayout.Label($"Alignment: {Mathf.RoundToInt(avatar.alignment * 100)}%");
            avatar.SetAlignment(GUILayout.HorizontalSlider(avatar.alignment, 0f, 1f));
            if (avatar.chakras != null)
                GUILayout.Label($"Dimmest chakra: {avatar.chakras.Weakest}");
            GUILayout.EndArea();
        }
    }
}

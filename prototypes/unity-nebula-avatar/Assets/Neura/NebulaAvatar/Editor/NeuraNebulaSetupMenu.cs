using UnityEditor;
using UnityEngine;

namespace Neura.Avatar.EditorTools
{
    /// <summary>One-click setup: select Neura's humanoid model, then GameObject > Neura > Make Nebula Avatar.</summary>
    public static class NeuraNebulaSetupMenu
    {
        [MenuItem("GameObject/Neura/Make Nebula Avatar", false, 10)]
        static void MakeNebulaAvatar()
        {
            var go = Selection.activeGameObject;
            if (go == null) { EditorUtility.DisplayDialog("Neura", "Select Neura's humanoid model first.", "OK"); return; }
            var animator = go.GetComponentInChildren<Animator>();
            if (animator == null || !animator.isHuman)
            {
                EditorUtility.DisplayDialog("Neura", "The selection needs an Animator with a Humanoid avatar.", "OK");
                return;
            }

            SkinnedMeshRenderer biggest = null;
            int most = -1;
            foreach (var smr in go.GetComponentsInChildren<SkinnedMeshRenderer>(true))
            {
                if (smr.sharedMesh == null) continue;
                if (smr.sharedMesh.vertexCount > most) { most = smr.sharedMesh.vertexCount; biggest = smr; }
            }
            if (biggest == null) { EditorUtility.DisplayDialog("Neura", "No skinned mesh found under the selection.", "OK"); return; }

            Undo.RegisterFullObjectHierarchyUndo(go, "Make Nebula Avatar");

            var body = GetOrAdd<NeuraPointCloudBody>(go);
            body.source = biggest;
            body.dissolveFrom = animator.GetBoneTransform(HumanBodyBones.Hips);

            var chakras = GetOrAdd<NeuraChakraSystem>(go);
            chakras.animator = animator;

            var avatar = GetOrAdd<NeuraNebulaAvatar>(go);
            avatar.body = body;
            avatar.chakras = chakras;
            avatar.visualRoot = animator.transform;
            avatar.headBone = animator.GetBoneTransform(HumanBodyBones.Head);
            avatar.face = biggest;

            var chest = animator.GetBoneTransform(HumanBodyBones.Chest);
            if (chest == null) chest = animator.GetBoneTransform(HumanBodyBones.Spine);
            if (chest != null && avatar.heartLight == null)
            {
                var lightGo = new GameObject("Neura Heart Light");
                Undo.RegisterCreatedObjectUndo(lightGo, "Neura Heart Light");
                lightGo.transform.SetParent(chest, false);
                lightGo.transform.localPosition = Vector3.zero;
                var l = lightGo.AddComponent<Light>();
                l.type = LightType.Point;
                l.range = 1.2f;
                l.intensity = 1.2f;
                l.shadows = LightShadows.None;
                avatar.heartLight = l;
            }

            var importer = AssetImporter.GetAtPath(AssetDatabase.GetAssetPath(biggest.sharedMesh)) as ModelImporter;
            if (importer != null && !importer.isReadable)
            {
                if (EditorUtility.DisplayDialog("Neura", "Neura's points need Read/Write enabled on this model. Turn it on now?", "Enable", "Skip"))
                {
                    importer.isReadable = true;
                    importer.SaveAndReimport();
                }
            }

            EditorUtility.SetDirty(go);
            Debug.Log("[Neura] Nebula avatar set up. Add Bloom to your post-processing volume for her glow.", go);
        }

        static T GetOrAdd<T>(GameObject go) where T : Component
        {
            return go.TryGetComponent(out T existing) ? existing : Undo.AddComponent<T>(go);
        }
    }
}

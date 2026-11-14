using System;
using System.Collections.Generic;
using UnityEngine;

namespace Neura.Avatar
{
    /// <summary>
    /// Turns a skinned humanoid mesh into Neura's starlight body:
    /// tens of thousands of lit points on her skin, plus a soft nebula flowing just inside it.
    /// Follows the animated skeleton every frame, so any animation or NavMesh movement just works.
    ///
    /// Optional vertex colors on the source mesh (paint them in Blender or similar):
    ///   red   = point density (paint eyes, lips, hands brighter red for more detail there)
    ///   green = feature glow (eyes, lips, fingertips, markings shine brighter and larger)
    ///   blue  = accent tint (bioluminescent markings take her mood's accent color)
    /// </summary>
    [DefaultExecutionOrder(100)]
    public class NeuraPointCloudBody : MonoBehaviour
    {
        [Header("Source")]
        [Tooltip("The humanoid's skinned mesh. Its own rendering is hidden; its shape drives the points.")]
        public SkinnedMeshRenderer source;
        public bool hideSourceMesh = true;
        [Tooltip("Use the mesh's vertex colors as density / glow / accent maps (see class notes).")]
        public bool useVertexColorMaps = false;
        public int randomSeed = 20261114;

        [Header("Starlight points")]
        [Range(2000, 120000)] public int pointCount = 40000;
        [Tooltip("World size of one point, in meters.")]
        public float pointSize = 0.0065f;
        [Tooltip("Directional light used to shade the points. Defaults to the scene's sun.")]
        public Light keyLight;
        [Range(0f, 1f)] public float ambient = 0.28f;
        public Color rimColor = new Color(1f, 0.97f, 0.92f);
        [Range(0f, 2f)] public float rimStrength = 0.9f;

        [Header("Inner nebula")]
        [Range(0, 4000)] public int nebulaCount = 900;
        [Tooltip("How far inside her skin the nebula sits, in meters.")]
        public Vector2 nebulaDepth = new Vector2(0.015f, 0.06f);
        public Vector2 nebulaSize = new Vector2(0.05f, 0.18f);
        [Range(0f, 1f)] public float nebulaOpacity = 0.22f;
        [Tooltip("How far the nebula drifts around, in meters.")]
        public float nebulaDrift = 0.025f;

        [Header("Floating: body dissolves into energy below this bone")]
        [Tooltip("Usually the hips. Leave empty to keep the whole body solid.")]
        public Transform dissolveFrom;
        public float dissolveRange = 0.5f;
        public float trailLength = 0.35f;

        [Header("Materials (optional; created automatically if empty)")]
        public Material pointMaterial;
        public Material nebulaMaterial;

        /// <summary>Set every frame by NeuraNebulaAvatar.</summary>
        [NonSerialized] public NeuraMoodLook look;
        /// <summary>1 = full motion, 0 = Still (Safe Mode). Set by NeuraNebulaAvatar.</summary>
        [NonSerialized] public float motion = 1f;
        float clock;

        ParticleSystem pointsPS, nebulaPS;
        ParticleSystem.Particle[] pts, neb;
        Mesh baked;
        int[] tris;
        readonly List<Vector3> verts = new List<Vector3>();
        readonly List<Vector3> norms = new List<Vector3>();

        // per point
        int[] pTri; Vector3[] pBary; float[] pPhase, pSeed, pFeature, pAccent;
        // per nebula puff
        int[] nTri; Vector3[] nBary; float[] nDepth, nPhase, nSize; int[] nCol;

        bool ready;

        void Awake()
        {
            look = NeuraMoodLibrary.Get(NeuraEmotion.Calm);
        }

        void Start()
        {
            if (source == null) source = GetComponentInChildren<SkinnedMeshRenderer>();
            if (source == null || source.sharedMesh == null)
            {
                Debug.LogWarning("[Neura] NeuraPointCloudBody needs a SkinnedMeshRenderer.", this);
                enabled = false;
                return;
            }
            if (!source.sharedMesh.isReadable)
            {
                Debug.LogWarning("[Neura] Enable Read/Write on the model's import settings so Neura's points can follow it.", source);
                enabled = false;
                return;
            }
            source.updateWhenOffscreen = true;
            if (hideSourceMesh) source.forceRenderingOff = true;
            if (keyLight == null) keyLight = RenderSettings.sun;

            if (pointMaterial == null) pointMaterial = NeuraFxUtil.CreateAdditive(NeuraFxUtil.SoftDot(64, 2.4f), "Neura Points");
            if (nebulaMaterial == null) nebulaMaterial = NeuraFxUtil.CreateAdditive(NeuraFxUtil.SoftDot(128, 1.6f), "Neura Nebula");

            pointsPS = NeuraFxUtil.CreateManualParticleSystem(transform, "Neura Starlight Points", pointCount, pointMaterial, 0.05f);
            nebulaPS = NeuraFxUtil.CreateManualParticleSystem(transform, "Neura Inner Nebula", Mathf.Max(1, nebulaCount), nebulaMaterial, 0.6f);

            BuildSampling();
            ready = true;
        }

        void BuildSampling()
        {
            baked = new Mesh { name = "Neura Baked" };
            source.BakeMesh(baked, true);
            var mesh = source.sharedMesh;
            tris = mesh.triangles;
            baked.GetVertices(verts);
            Color[] vcol = useVertexColorMaps ? mesh.colors : null;
            bool hasCol = vcol != null && vcol.Length == verts.Count;

            int triCount = tris.Length / 3;
            var cdf = new float[triCount];
            var cdfUniform = new float[triCount];
            float total = 0f, totalU = 0f;
            for (int t = 0; t < triCount; t++)
            {
                int a = tris[t * 3], b = tris[t * 3 + 1], c = tris[t * 3 + 2];
                float area = Vector3.Cross(verts[b] - verts[a], verts[c] - verts[a]).magnitude * 0.5f;
                float w = hasCol ? 0.15f + (vcol[a].r + vcol[b].r + vcol[c].r) / 3f : 1f;
                total += area * w; cdf[t] = total;
                totalU += area; cdfUniform[t] = totalU;
            }

            var rng = new System.Random(randomSeed);
            pts = new ParticleSystem.Particle[pointCount];
            pTri = new int[pointCount]; pBary = new Vector3[pointCount];
            pPhase = new float[pointCount]; pSeed = new float[pointCount];
            pFeature = new float[pointCount]; pAccent = new float[pointCount];
            for (int i = 0; i < pointCount; i++)
            {
                int t = Pick(cdf, (float)rng.NextDouble() * total);
                var bary = RandomBary(rng);
                pTri[i] = t * 3; pBary[i] = bary;
                pPhase[i] = (float)rng.NextDouble() * Mathf.PI * 2f;
                pSeed[i] = (float)rng.NextDouble();
                if (hasCol)
                {
                    int a = tris[t * 3], b = tris[t * 3 + 1], c = tris[t * 3 + 2];
                    Color col = vcol[a] * bary.x + vcol[b] * bary.y + vcol[c] * bary.z;
                    pFeature[i] = col.g; pAccent[i] = col.b;
                }
                pts[i].startLifetime = 1000f;
                pts[i].remainingLifetime = 1000f;
            }

            neb = new ParticleSystem.Particle[nebulaCount];
            nTri = new int[nebulaCount]; nBary = new Vector3[nebulaCount];
            nDepth = new float[nebulaCount]; nPhase = new float[nebulaCount]; nSize = new float[nebulaCount]; nCol = new int[nebulaCount];
            for (int i = 0; i < nebulaCount; i++)
            {
                int t = Pick(cdfUniform, (float)rng.NextDouble() * totalU);
                nTri[i] = t * 3; nBary[i] = RandomBary(rng);
                nDepth[i] = Mathf.Lerp(nebulaDepth.x, nebulaDepth.y, (float)rng.NextDouble());
                nPhase[i] = (float)rng.NextDouble() * 100f;
                nSize[i] = Mathf.Lerp(nebulaSize.x, nebulaSize.y, (float)rng.NextDouble());
                nCol[i] = rng.Next(8);
                neb[i].startLifetime = 1000f;
                neb[i].remainingLifetime = 1000f;
                neb[i].rotation = (float)rng.NextDouble() * 360f;
            }
        }

        static int Pick(float[] cdf, float r)
        {
            int idx = Array.BinarySearch(cdf, r);
            if (idx < 0) idx = ~idx;
            return Mathf.Clamp(idx, 0, cdf.Length - 1);
        }

        static Vector3 RandomBary(System.Random rng)
        {
            float u = (float)rng.NextDouble(), v = (float)rng.NextDouble();
            if (u + v > 1f) { u = 1f - u; v = 1f - v; }
            return new Vector3(1f - u - v, u, v);
        }

        void LateUpdate()
        {
            if (!ready) return;
            source.BakeMesh(baked, true);
            baked.GetVertices(verts);
            baked.GetNormals(norms);
            if (norms.Count != verts.Count) return;

            var st = source.transform;
            Matrix4x4 m = Matrix4x4.TRS(st.position, st.rotation, Vector3.one);
            Vector3 L = keyLight != null ? -keyLight.transform.forward : new Vector3(-0.4f, 0.6f, -0.7f).normalized;
            var cam = Camera.main;
            Vector3 camPos = cam != null ? cam.transform.position : st.position + st.forward * 2f;
            clock += Time.deltaTime * Mathf.Clamp01(motion);
            float time = clock;
            float dissolveY = dissolveFrom != null ? dissolveFrom.position.y : float.NegativeInfinity;
            var lk = look;
            Color accent = lk.accent;

            // ---- Starlight points on her skin ----
            for (int i = 0; i < pts.Length; i++)
            {
                int k = pTri[i];
                int a = tris[k], b = tris[k + 1], c = tris[k + 2];
                Vector3 bc = pBary[i];
                Vector3 p = m.MultiplyPoint3x4(verts[a] * bc.x + verts[b] * bc.y + verts[c] * bc.z);
                Vector3 n = m.MultiplyVector(norms[a] * bc.x + norms[b] * bc.y + norms[c] * bc.z).normalized;

                float diff = Mathf.Max(0f, Vector3.Dot(n, L));
                Vector3 V = (camPos - p).normalized;
                float rim = Mathf.Pow(1f - Mathf.Max(0f, Vector3.Dot(n, V)), 3f) * rimStrength;
                float twinkle = 1f - lk.sparkle * 0.55f * (0.5f + 0.5f * Mathf.Sin(time * (1.2f + pSeed[i] * 2.4f) + pPhase[i]));
                float feature = pFeature[i];
                float lum = (ambient + (1f - ambient) * diff) * lk.brightness * twinkle * (1f + feature * 1.6f);

                Color baseCol = pSeed[i] < 0.12f ? Color.Lerp(Color.white, accent, 0.65f)
                              : pSeed[i] < 0.2f ? Color.Lerp(Color.white, lk.heart, 0.5f)
                              : Color.white;
                baseCol = Color.Lerp(baseCol, accent, pAccent[i]);
                Color col = baseCol * lum + rimColor * rim * 0.6f;

                float alpha = 0.55f + 0.45f * pSeed[i];
                if (p.y < dissolveY)
                {
                    float f = Mathf.Clamp01((dissolveY - p.y) / dissolveRange);
                    alpha *= 1f - f;
                    float flow = Mathf.Repeat(time * 0.12f * lk.floatSpeed + pPhase[i] * 0.16f, 1f);
                    p += Vector3.down * (f * trailLength * flow);
                    p += new Vector3(Mathf.Sin(time * 0.7f + pPhase[i]), 0f, Mathf.Cos(time * 0.6f + pPhase[i])) * (f * 0.05f);
                }
                col.a = alpha;

                pts[i].position = p;
                pts[i].startSize = pointSize * (0.6f + 0.55f * diff + 0.5f * pSeed[i]) * (1f + feature * 0.7f);
                pts[i].startColor = col;
            }
            pointsPS.SetParticles(pts, pts.Length);

            // ---- Nebula just inside her skin ----
            float drift = time * 0.18f * lk.driftSpeed;
            for (int i = 0; i < neb.Length; i++)
            {
                int k = nTri[i];
                int a = tris[k], b = tris[k + 1], c = tris[k + 2];
                Vector3 bc = nBary[i];
                Vector3 p = m.MultiplyPoint3x4(verts[a] * bc.x + verts[b] * bc.y + verts[c] * bc.z);
                Vector3 n = m.MultiplyVector(norms[a] * bc.x + norms[b] * bc.y + norms[c] * bc.z).normalized;
                p -= n * nDepth[i];
                float ph = nPhase[i];
                p += new Vector3(Mathf.PerlinNoise(drift, ph) - 0.5f, Mathf.PerlinNoise(ph, drift) - 0.5f, Mathf.PerlinNoise(drift + 37f, ph + 11f) - 0.5f) * (2f * nebulaDrift);

                float alpha = nebulaOpacity * lk.brightness;
                if (p.y < dissolveY) alpha *= 1f - Mathf.Clamp01((dissolveY - p.y) / (dissolveRange * 0.6f));
                Color col = lk.nebula[nCol[i]];
                col.a = alpha;

                neb[i].position = p;
                neb[i].startSize = nSize[i] * (0.85f + 0.3f * Mathf.PerlinNoise(drift * 0.5f, ph * 0.3f));
                neb[i].startColor = col;
                neb[i].rotation += Time.deltaTime * 6f * lk.driftSpeed * Mathf.Clamp01(motion);
            }
            if (neb.Length > 0) nebulaPS.SetParticles(neb, neb.Length);
        }

        void OnDisable()
        {
            if (source != null && hideSourceMesh) source.forceRenderingOff = false;
        }
    }
}

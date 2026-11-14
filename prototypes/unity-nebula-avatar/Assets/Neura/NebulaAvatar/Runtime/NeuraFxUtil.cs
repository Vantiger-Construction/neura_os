using UnityEngine;
using UnityEngine.Rendering;

namespace Neura.Avatar
{
    /// <summary>Procedural textures, additive materials and particle-system setup shared by the avatar.</summary>
    public static class NeuraFxUtil
    {
        /// <summary>Soft round glow: white, alpha falling off from the center.</summary>
        public static Texture2D SoftDot(int size = 64, float hardness = 2.2f)
        {
            var tex = new Texture2D(size, size, TextureFormat.RGBA32, false) { wrapMode = TextureWrapMode.Clamp, name = "NeuraSoftDot" };
            var px = new Color32[size * size];
            float c = (size - 1) * 0.5f;
            for (int y = 0; y < size; y++)
            for (int x = 0; x < size; x++)
            {
                float d = Mathf.Sqrt((x - c) * (x - c) + (y - c) * (y - c)) / c;
                float a = Mathf.Pow(Mathf.Clamp01(1f - d), hardness);
                px[y * size + x] = new Color32(255, 255, 255, (byte)(a * 255));
            }
            tex.SetPixels32(px);
            tex.Apply();
            return tex;
        }

        /// <summary>A thin ring broken into petals, for the turning chakra rings.</summary>
        public static Texture2D PetalRing(int size = 128, int petals = 12)
        {
            var tex = new Texture2D(size, size, TextureFormat.RGBA32, false) { wrapMode = TextureWrapMode.Clamp, name = "NeuraPetalRing" };
            var px = new Color32[size * size];
            float c = (size - 1) * 0.5f;
            for (int y = 0; y < size; y++)
            for (int x = 0; x < size; x++)
            {
                float dx = x - c, dy = y - c;
                float d = Mathf.Sqrt(dx * dx + dy * dy) / c;
                float ring = Mathf.Clamp01(1f - Mathf.Abs(d - 0.78f) / 0.07f);
                float ang = Mathf.Atan2(dy, dx);
                float petal = Mathf.Clamp01(Mathf.Cos(ang * petals) * 0.5f + 0.6f);
                float a = ring * petal;
                px[y * size + x] = new Color32(255, 255, 255, (byte)(a * 255));
            }
            tex.SetPixels32(px);
            tex.Apply();
            return tex;
        }

        /// <summary>A dash pattern for the energy channel. duty = share of each repeat that is lit.</summary>
        public static Texture2D Dash(float duty, Texture2D reuse = null)
        {
            const int w = 64, h = 4;
            var tex = reuse != null ? reuse : new Texture2D(w, h, TextureFormat.RGBA32, false) { wrapMode = TextureWrapMode.Repeat, name = "NeuraDash" };
            var px = new Color32[w * h];
            int lit = Mathf.Clamp(Mathf.RoundToInt(duty * w), 2, w);
            for (int x = 0; x < w; x++)
            {
                float edge = Mathf.Min(x, lit - 1 - x);
                byte a = x < lit ? (byte)(Mathf.Clamp01(edge / 3f + 0.35f) * 255) : (byte)0;
                for (int y = 0; y < h; y++) px[y * w + x] = new Color32(255, 255, 255, a);
            }
            tex.SetPixels32(px);
            tex.Apply();
            return tex;
        }

        /// <summary>
        /// Builds an additive, unlit, transparent material for particles or lines.
        /// Works with URP and the built-in pipeline. For builds, add the shader it finds to
        /// Project Settings > Graphics > Always Included Shaders, or assign your own material instead.
        /// </summary>
        public static Material CreateAdditive(Texture tex, string name)
        {
            Shader sh = Shader.Find("Universal Render Pipeline/Particles/Unlit");
            Material m;
            if (sh != null)
            {
                m = new Material(sh) { name = name };
                m.SetFloat("_Surface", 1f);
                m.SetFloat("_Blend", 2f);
                m.SetOverrideTag("RenderType", "Transparent");
                m.SetInt("_SrcBlend", (int)BlendMode.SrcAlpha);
                m.SetInt("_DstBlend", (int)BlendMode.One);
                m.SetInt("_ZWrite", 0);
                m.EnableKeyword("_SURFACE_TYPE_TRANSPARENT");
                m.EnableKeyword("_BLENDMODE_ADD");
                m.renderQueue = (int)RenderQueue.Transparent;
            }
            else if ((sh = Shader.Find("Particles/Standard Unlit")) != null)
            {
                m = new Material(sh) { name = name };
                m.SetFloat("_Mode", 4f);
                m.SetInt("_SrcBlend", (int)BlendMode.SrcAlpha);
                m.SetInt("_DstBlend", (int)BlendMode.One);
                m.SetInt("_ZWrite", 0);
                m.EnableKeyword("_ALPHABLEND_ON");
                m.renderQueue = (int)RenderQueue.Transparent;
            }
            else
            {
                sh = Shader.Find("Legacy Shaders/Particles/Additive") ?? Shader.Find("Sprites/Default");
                m = new Material(sh) { name = name };
            }
            m.mainTexture = tex;
            if (m.HasProperty("_BaseColor")) m.SetColor("_BaseColor", Color.white);
            if (m.HasProperty("_Color")) m.SetColor("_Color", Color.white);
            return m;
        }

        /// <summary>A child ParticleSystem we fill by hand every frame (no emission, no simulation of its own).</summary>
        public static ParticleSystem CreateManualParticleSystem(Transform parent, string name, int maxParticles, Material mat, float maxScreenSize = 0.5f)
        {
            var go = new GameObject(name);
            go.transform.SetParent(parent, false);
            var ps = go.AddComponent<ParticleSystem>();
            ps.Stop(true, ParticleSystemStopBehavior.StopEmittingAndClear);

            var main = ps.main;
            main.loop = true;
            main.playOnAwake = false;
            main.duration = 1f;
            main.maxParticles = maxParticles;
            main.simulationSpace = ParticleSystemSimulationSpace.World;
            main.startSpeed = 0f;
            main.startLifetime = 1000f;
            main.gravityModifier = 0f;
            main.scalingMode = ParticleSystemScalingMode.Shape;

            var emission = ps.emission;
            emission.enabled = false;
            var shape = ps.shape;
            shape.enabled = false;

            var r = go.GetComponent<ParticleSystemRenderer>();
            r.sharedMaterial = mat;
            r.renderMode = ParticleSystemRenderMode.Billboard;
            r.sortMode = ParticleSystemSortMode.None;
            r.shadowCastingMode = ShadowCastingMode.Off;
            r.receiveShadows = false;
            r.minParticleSize = 0f;
            r.maxParticleSize = maxScreenSize;

            ps.Play();
            return ps;
        }
    }
}

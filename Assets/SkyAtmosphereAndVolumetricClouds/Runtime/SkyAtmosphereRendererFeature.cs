using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

namespace UnityEngine.Rendering.Universal
{
    internal class SkyAtmosphereRendererFeature : ScriptableRendererFeature
    {

#if UNITY_EDITOR
        public static readonly string packagePath = "Assets/SkyAtmosphereAndVolumetricClouds";
#endif
        
        [Reload("Shaders/SkyAtmosphereApply.shader"), HideInInspector]
        public Shader skyAtmosphereApplyShader;
        
        [Reload("Shaders/SkyAtmosphere.compute"), HideInInspector]
        public ComputeShader skyAtmosphereComputeShader;

        private SkyAtmosphereLutRenderPass m_LutRenderPass;
        private SkyAtmosphereApplyPass m_ApplyPass;

        public override void Create()
        {
#if UNITY_EDITOR
            ResourceReloader.TryReloadAllNullIn(this, packagePath);
#endif
            m_LutRenderPass = new SkyAtmosphereLutRenderPass(this);
            m_ApplyPass = new SkyAtmosphereApplyPass(this);
        }

        // Here you can inject one or multiple render passes in the renderer.
        // This method is called when setting up the renderer once per-camera.
        public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
        {
            var st = VolumeManager.instance.stack.GetComponent<SkyAtmosphere>();
            if (st.IsActive())
            {
                renderer.EnqueuePass(m_LutRenderPass);
                renderer.EnqueuePass(m_ApplyPass);
            }
        }

    }
}

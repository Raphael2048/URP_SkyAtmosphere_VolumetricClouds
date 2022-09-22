namespace UnityEngine.Rendering.Universal
{
    internal class SkyAtmosphereLutRenderPass : ScriptableRenderPass
    {
        private ProfilingSampler sampler;
        private SkyAtmosphereRendererFeature feature;
        internal RenderTexture m_TransmittanceLut, m_MultiScatteredLuminanceLut, m_SkyViewLut, m_CameraVolumeLut;

        private static readonly Vector2Int TransmittanceLutSize = new Vector2Int(256, 64);
        private static readonly Vector2Int MultiScatteredLutSize = new Vector2Int(32, 32);
        private static readonly Vector2Int SkyViewLutSize = new Vector2Int(192, 104);
        private static readonly Vector3Int CameraVolumeLutSize = new Vector3Int(32, 32, 16);
        private static readonly float SunOnEarthHalfAngleRadian = 0.545f * 0.5f * Mathf.PI / 180.0f;

        private Vector4[] Params = new Vector4[16];

        public SkyAtmosphereLutRenderPass(SkyAtmosphereRendererFeature feature)
        {
            this.feature = feature;
            this.renderPassEvent = RenderPassEvent.BeforeRenderingOpaques;
            sampler = new ProfilingSampler("SkyAtmosphere");
        }
        
        public static bool FetchRenderTexture(ref RenderTexture rt, RenderTextureDescriptor descriptor)
        {
            if (rt == null || rt.width != descriptor.width || rt.height != descriptor.height ||
                rt.volumeDepth != descriptor.volumeDepth)
            {
                if (rt) RenderTexture.ReleaseTemporary(rt);
                rt = RenderTexture.GetTemporary(descriptor);
                if (!rt.IsCreated()) rt.Create();
                return true;
            }
            return false;
        }
        
        // 散射系数中设置的单位是10^-6/m,转换成 1/km
        private static readonly float Coeff = 0.001f;
        public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
        {
            var sa = VolumeManager.instance.stack.GetComponent<SkyAtmosphere>();
            CommandBuffer cmd = CommandBufferPool.Get();
            using (new ProfilingScope(cmd, sampler))
            {
                Params[0] = sa.GroundAlbedo.value;
                Params[0].w = sa.AerialPerspective.value ? 1.0f : 0.0f;
                Params[1] = sa.RayleighScattering.value * Coeff;
                Params[1].w = Mathf.Max(1.0f / sa.RayleightExponentialDistribution.value, 0.001f);
                Params[2].x = sa.MieScattering.value * Coeff;
                Params[2].y = sa.MieAbsorption.value * Coeff;
                Params[2].z = sa.MieAnisotropy.value;
                Params[2].w = Mathf.Max(1.0f / sa.MieExponentialDistribution.value, 0.001f);
                Params[3] = sa.OzoneAbsorption.value * Coeff;
                Params[3].w = sa.OzoneAbsorptionTipAltitude.value;
                Params[4].x = sa.OzoneAbsorptionWidth.value;
                Params[4].y = Mathf.Max(sa.GroundRadius.value, 0) + Mathf.Max(sa.AtmosphereHeight.value, 0);
                Params[4].z = Mathf.Max(sa.GroundRadius.value, 0);
                Params[5] = new Vector4(TransmittanceLutSize.x, TransmittanceLutSize.y, 1.0f / TransmittanceLutSize.x,
                    1.0f / TransmittanceLutSize.y);
                Params[6] = new Vector4(MultiScatteredLutSize.x, MultiScatteredLutSize.y, 1.0f / MultiScatteredLutSize.x,
                    1.0f / MultiScatteredLutSize.y);
                Params[7] = new Vector4(SkyViewLutSize.x, SkyViewLutSize.y, 1.0f / SkyViewLutSize.x,
                    1.0f / SkyViewLutSize.y);
                Params[8] = new Vector4(1.0f / CameraVolumeLutSize.x, 1.0f / CameraVolumeLutSize.y,
                    1.0f / CameraVolumeLutSize.z, CameraVolumeLutSize.z);
                Params[9] = sa.LightDiskColor.value;
                Params[9].w = Mathf.Cos(sa.LightDiskSize.value * SunOnEarthHalfAngleRadian);
                Params[10].x = renderingData.cameraData.camera.farClipPlane * 0.001f / CameraVolumeLutSize.z; 
                Params[10].y = 1.0f / Params[10].x;
                cmd.SetGlobalVectorArray("_SkyAtmosphereParams", Params);
                
                var desc = new RenderTextureDescriptor();
                desc.width = TransmittanceLutSize.x;
                desc.enableRandomWrite = true;
                desc.height = TransmittanceLutSize.y;
                desc.colorFormat = RenderTextureFormat.RGB111110Float;
                desc.msaaSamples = 1;
                desc.dimension = TextureDimension.Tex2D;
                desc.volumeDepth = 1;
                FetchRenderTexture(ref m_TransmittanceLut, desc);

                desc.width = MultiScatteredLutSize.x;
                desc.height = MultiScatteredLutSize.y;
                FetchRenderTexture(ref m_MultiScatteredLuminanceLut, desc);

                desc.width = SkyViewLutSize.x;
                desc.height = SkyViewLutSize.y;
                FetchRenderTexture(ref m_SkyViewLut, desc);

                desc.width = CameraVolumeLutSize.x;
                desc.height = CameraVolumeLutSize.y;
                desc.volumeDepth = CameraVolumeLutSize.z;
                desc.dimension = TextureDimension.Tex3D;
                desc.colorFormat = RenderTextureFormat.ARGBHalf;
                FetchRenderTexture(ref m_CameraVolumeLut, desc);
                
                feature.skyAtmosphereComputeShader.SetTexture(0, "_RWTransmittanceLut", m_TransmittanceLut);
                cmd.DispatchCompute(feature.skyAtmosphereComputeShader, 0, TransmittanceLutSize.x / 8, TransmittanceLutSize.y / 8, 1);
                cmd.SetGlobalTexture("_TransmittanceLut", m_TransmittanceLut);
                
                feature.skyAtmosphereComputeShader.SetTexture(1, "_RWMultiScatteredLut", m_MultiScatteredLuminanceLut);
                cmd.DispatchCompute(feature.skyAtmosphereComputeShader, 1, MultiScatteredLutSize.x / 8, MultiScatteredLutSize.y / 8, 1);
                cmd.SetGlobalTexture("_MultiScatteredLut", m_MultiScatteredLuminanceLut);
                
                feature.skyAtmosphereComputeShader.SetTexture(2, "_RWSkyViewLut", m_SkyViewLut);
                cmd.DispatchCompute(feature.skyAtmosphereComputeShader, 2, SkyViewLutSize.x / 8, SkyViewLutSize.y / 8, 1);
                cmd.SetGlobalTexture("_SkyViewLut", m_SkyViewLut);

                if (sa.AerialPerspective.value)
                {
                    feature.skyAtmosphereComputeShader.SetTexture(3, "_RWCameraVolumeLut", m_CameraVolumeLut);
                    cmd.DispatchCompute(feature.skyAtmosphereComputeShader, 3, CameraVolumeLutSize.x / 4, CameraVolumeLutSize.y / 4, CameraVolumeLutSize.z / 4);
                }
                cmd.SetGlobalTexture("_CameraVolumeLut", m_CameraVolumeLut);
            }
            context.ExecuteCommandBuffer(cmd);
            cmd.Clear();
            CommandBufferPool.Release(cmd);
        }
    }
    
    internal class SkyAtmosphereApplyPass : ScriptableRenderPass
    {
        private ProfilingSampler sampler;
        private SkyAtmosphereRendererFeature feature;
        static Material skyAtmosphereApplyMaterial;
        
        public SkyAtmosphereApplyPass(SkyAtmosphereRendererFeature feature)
        {
            this.feature = feature;
            this.renderPassEvent = RenderPassEvent.AfterRenderingSkybox;
            sampler = new ProfilingSampler("SkyAtmosphereApply");
        }

        public override void Configure(CommandBuffer cmd, RenderTextureDescriptor cameraTextureDescriptor)
        {
            if (skyAtmosphereApplyMaterial == null)
            {
                skyAtmosphereApplyMaterial = CoreUtils.CreateEngineMaterial(feature.skyAtmosphereApplyShader);
            }
        }
        public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
        {
            CommandBuffer cmd = CommandBufferPool.Get();
            using (new ProfilingScope(cmd, sampler))
            {
                cmd.SetRenderTarget(renderingData.cameraData.renderer.cameraColorTarget);
                cmd.DrawProcedural(Matrix4x4.identity, skyAtmosphereApplyMaterial, 0, MeshTopology.Triangles,3);
            }
            context.ExecuteCommandBuffer(cmd);
            cmd.Clear();
            CommandBufferPool.Release(cmd);
        }
    }
}

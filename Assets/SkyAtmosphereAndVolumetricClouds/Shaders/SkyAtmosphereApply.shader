Shader "Hidden/SkyAtmospherApply"
{
	Properties
	{
		_MainTex("Base (RGB)", 2D) = "white" {}
	}

	SubShader
	{
		Tags{ "Queue" = "Overlay" "RenderType" = "Overlay" }
		
		HLSLINCLUDE
			#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/SurfaceInput.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Common.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            
			#include "SkyAtmosphere.hlsl"
			//#pragma enable_d3d11_debug_symbols
		
			struct ProceduralAttributes
			{
				uint vertexID : VERTEXID_SEMANTIC;
			};
		
			struct ProceduralVaryings
			{
				float4 positionCS : SV_POSITION;
				float2 uv : TEXCOORD;
			};

			ProceduralVaryings ProceduralVert(ProceduralAttributes input)
			{
				ProceduralVaryings output;
				output.positionCS = GetFullScreenTriangleVertexPosition(input.vertexID);
				output.uv = GetFullScreenTriangleTexCoord(input.vertexID);
				return output;
			}
		
			float4 frag(ProceduralVaryings i) : SV_Target
			{
				float depth = _CameraDepthTexture.Load(int3(i.positionCS.xy, 0));
				float2 UV = i.positionCS.xy * _ScreenSize.zw;
				if (depth == UNITY_RAW_FAR_CLIP_VALUE)
				{
					float3 WorldDir = UnityDirectionToAtmosphereDirection(GetWorldDir(UV));
					float ViewHeight = GetCameraViewHeight();
					float3 WorldPos = float3(0, 0, ViewHeight);
					
					float3 LightDiskLuminance = GetLightDiskLuminance(WorldPos, WorldDir);

					float ViewZenithCosAngle = dot(WorldDir, float3(0, 0, 1));
					bool IntersectGround = RaySphereIntersectNearest(WorldPos, WorldDir, float3(0, 0, 0), BottomRadiusKm) >= 0.0f;
					SkyViewLutParamsToUv(IntersectGround, ViewZenithCosAngle, WorldDir, ViewHeight, BottomRadiusKm, SkyViewLutSize, UV);
					float3 SkyLuminance = _SkyViewLut.SampleLevel(sampler_LinearClamp, UV, 0).rgb;
					return float4(LightDiskLuminance + SkyLuminance, 0);
				}
				else if (EnableAeraialPerspective)
				{
					float3 NDCPos = float3(UV * 2 - 1, depth);
#if UNITY_REVERSE_Z
	NDCPos.y = - NDCPos.y;
#else
	NDCPos.z = NDCPos.z * 2 - 1;
#endif
					float4 WorldPos = mul(UNITY_MATRIX_I_VP, float4(NDCPos, 1));
					WorldPos /= WorldPos.w;
					float Distance = length(WorldPos.xyz - _WorldSpaceCameraPos.xyz);
					float4 AP = GetAerialPerspectiveLuminanceTransmittance(UV, Distance * 0.001f);
					return AP;
				}
				else
				{
					return float4(0, 0, 0, 1);
				}
			}
		ENDHLSL
		// 0
		Pass
		{
			Cull Off
			ZWrite Off
			ZTest Off
			Stencil
			{
				Ref 2
				Comp NotEqual
			}
			Blend One SrcAlpha
			HLSLPROGRAM
			#pragma vertex ProceduralVert
			#pragma fragment frag
			ENDHLSL
		}
	}
}
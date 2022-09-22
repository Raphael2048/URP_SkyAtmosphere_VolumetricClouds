using System;
using System.Diagnostics;

namespace UnityEngine.Rendering.Universal
{
    [Serializable, VolumeComponentMenu("Custom/SkyAtmosphere")]
    public class SkyAtmosphere : VolumeComponent, IPostProcessComponent
    {
        public BoolParameter Active = new BoolParameter(false);
        public BoolParameter AerialPerspective = new BoolParameter(false);
        // public BoolParameter AutoMainLightLuminance = new BoolParameter(false);
        public FloatParameter GroundRadius = new FloatParameter(6360);
        public ColorParameter GroundAlbedo = new ColorParameter(Color.grey, false, false, false, false);
        public FloatParameter AtmosphereHeight = new FloatParameter(60);
        public Vector3Parameter RayleighScattering = new Vector3Parameter(new Vector3(5.802f, 13.558f, 33.1f));
        public FloatParameter RayleightExponentialDistribution = new FloatParameter(8);
        public FloatParameter MieScattering = new FloatParameter(3.996f);
        public FloatParameter MieAbsorption = new FloatParameter(4.40f);
        public ClampedFloatParameter MieAnisotropy = new ClampedFloatParameter(0.8f, 0.0f, 1.0f);
        public FloatParameter MieExponentialDistribution = new FloatParameter(1.2f);
        public Vector3Parameter OzoneAbsorption = new Vector3Parameter(new Vector3(0.650f, 1.881f, 0.085f));
        public FloatParameter OzoneAbsorptionTipAltitude = new FloatParameter(25.0f);
        public FloatParameter OzoneAbsorptionWidth = new FloatParameter(15.0f);
        public ColorParameter LightDiskColor = new ColorParameter(Color.white, true, false, false);
        public ClampedFloatParameter LightDiskSize = new ClampedFloatParameter(1.0f, 0.1f, 20.0f);
        public bool IsActive()
        {
            return Active.value;
        }
        
        public bool IsTileCompatible()
        {
            return false;
        }
    }
}
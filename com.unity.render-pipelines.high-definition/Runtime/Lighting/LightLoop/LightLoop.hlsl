#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Macros.hlsl"

#if defined(PROBE_VOLUMES_L1) || defined(PROBE_VOLUMES_L2)
#include "Packages/com.unity.render-pipelines.high-definition/Runtime/Material/BuiltinUtilities.hlsl"
#else
// Required to have access to the indirectDiffuseMode enum in forward pass where we don't include BuiltinUtilities
#include "Packages/com.unity.render-pipelines.high-definition/Runtime/Lighting/ScreenSpaceLighting/ScreenSpaceGlobalIllumination.cs.hlsl"
#endif

#ifndef SCALARIZE_LIGHT_LOOP
// We perform scalarization only for forward rendering as for deferred loads will already be scalar since tiles will match waves and therefore all threads will read from the same tile.
// More info on scalarization: https://flashypixels.wordpress.com/2018/11/10/intro-to-gpu-scalarization-part-2-scalarize-all-the-lights/
#define SCALARIZE_LIGHT_LOOP (defined(PLATFORM_SUPPORTS_WAVE_INTRINSICS) && !defined(LIGHTLOOP_DISABLE_TILE_AND_CLUSTER) && SHADERPASS == SHADERPASS_FORWARD)
#endif


//-----------------------------------------------------------------------------
// LightLoop
// ----------------------------------------------------------------------------

void ApplyDebugToLighting(LightLoopContext context, inout BuiltinData builtinData, inout AggregateLighting aggregateLighting)
{
#ifdef DEBUG_DISPLAY
    if (_DebugLightingMode >= DEBUGLIGHTINGMODE_DIFFUSE_LIGHTING && _DebugLightingMode <= DEBUGLIGHTINGMODE_EMISSIVE_LIGHTING)
    {
        if (_DebugLightingMode == DEBUGLIGHTINGMODE_SPECULAR_LIGHTING ||
            _DebugLightingMode == DEBUGLIGHTINGMODE_DIRECT_SPECULAR_LIGHTING ||
            _DebugLightingMode == DEBUGLIGHTINGMODE_INDIRECT_DIFFUSE_LIGHTING ||
            _DebugLightingMode == DEBUGLIGHTINGMODE_REFLECTION_LIGHTING ||
            _DebugLightingMode == DEBUGLIGHTINGMODE_REFRACTION_LIGHTING ||
            _DebugLightingMode == DEBUGLIGHTINGMODE_EMISSIVE_LIGHTING)
        {
            aggregateLighting.direct.diffuse = real3(0.0, 0.0, 0.0);
        }

        if (_DebugLightingMode == DEBUGLIGHTINGMODE_DIFFUSE_LIGHTING ||
            _DebugLightingMode == DEBUGLIGHTINGMODE_DIRECT_DIFFUSE_LIGHTING ||
            _DebugLightingMode == DEBUGLIGHTINGMODE_INDIRECT_DIFFUSE_LIGHTING ||
            _DebugLightingMode == DEBUGLIGHTINGMODE_REFLECTION_LIGHTING ||
            _DebugLightingMode == DEBUGLIGHTINGMODE_REFRACTION_LIGHTING ||
            _DebugLightingMode == DEBUGLIGHTINGMODE_EMISSIVE_LIGHTING)
        {
            aggregateLighting.direct.specular = real3(0.0, 0.0, 0.0);
        }

        if (_DebugLightingMode == DEBUGLIGHTINGMODE_DIFFUSE_LIGHTING ||
            _DebugLightingMode == DEBUGLIGHTINGMODE_DIRECT_DIFFUSE_LIGHTING ||
            _DebugLightingMode == DEBUGLIGHTINGMODE_DIRECT_SPECULAR_LIGHTING ||
            _DebugLightingMode == DEBUGLIGHTINGMODE_INDIRECT_DIFFUSE_LIGHTING ||
            _DebugLightingMode == DEBUGLIGHTINGMODE_REFRACTION_LIGHTING ||
            _DebugLightingMode == DEBUGLIGHTINGMODE_EMISSIVE_LIGHTING)
        {
            aggregateLighting.indirect.specularReflected = real3(0.0, 0.0, 0.0);
        }

        // Note: specular transmission is the refraction and as it reflect lighting behind the object it
        // must be displayed for both diffuse and specular mode, except if we ask for direct lighting only
        if (_DebugLightingMode != DEBUGLIGHTINGMODE_REFRACTION_LIGHTING)
        {
            aggregateLighting.indirect.specularTransmitted = real3(0.0, 0.0, 0.0);
        }

        if (_DebugLightingMode == DEBUGLIGHTINGMODE_SPECULAR_LIGHTING ||
            _DebugLightingMode == DEBUGLIGHTINGMODE_DIRECT_DIFFUSE_LIGHTING ||
            _DebugLightingMode == DEBUGLIGHTINGMODE_DIRECT_SPECULAR_LIGHTING ||
            _DebugLightingMode == DEBUGLIGHTINGMODE_REFLECTION_LIGHTING ||
            _DebugLightingMode == DEBUGLIGHTINGMODE_REFRACTION_LIGHTING
#if (SHADERPASS != SHADERPASS_DEFERRED_LIGHTING)
            || _DebugLightingMode == DEBUGLIGHTINGMODE_EMISSIVE_LIGHTING // With deferred, Emissive is store in builtinData.bakeDiffuseLighting
#endif
            )
        {
            builtinData.bakeDiffuseLighting = real3(0.0, 0.0, 0.0);
        }

        if (_DebugLightingMode != DEBUGLIGHTINGMODE_EMISSIVE_LIGHTING)
        {
            builtinData.emissiveColor = real3(0.0, 0.0, 0.0);
        }
    }
#endif
}

void ApplyDebug(LightLoopContext context, PositionInputs posInput, BSDFData bsdfData, inout LightLoopOutput lightLoopOutput)
{
#ifdef DEBUG_DISPLAY
    if (_DebugLightingMode == DEBUGLIGHTINGMODE_PROBE_VOLUME)
    {
        // Debug info is written to diffuseColor inside of light loop.
        lightLoopOutput.specularLighting = float3(0.0, 0.0, 0.0);
    }
    else if (_DebugLightingMode == DEBUGLIGHTINGMODE_LUX_METER)
    {
        lightLoopOutput.specularLighting = float3(0.0, 0.0, 0.0); // Disable specular lighting
        // Take the luminance
        lightLoopOutput.diffuseLighting = Luminance(lightLoopOutput.diffuseLighting).xxx;
    }
    else if (_DebugLightingMode == DEBUGLIGHTINGMODE_VISUALIZE_CASCADE)
    {
        lightLoopOutput.specularLighting = float3(0.0, 0.0, 0.0);

        const float3 s_CascadeColors[] = {
            float3(0.5, 0.5, 0.7),
            float3(0.5, 0.7, 0.5),
            float3(0.7, 0.7, 0.5),
            float3(0.7, 0.5, 0.5),
            float3(1.0, 1.0, 1.0)
        };

        lightLoopOutput.diffuseLighting = Luminance(lightLoopOutput.diffuseLighting);
        if (_DirectionalShadowIndex >= 0)
        {
            real alpha;
            int cascadeCount;

            int shadowSplitIndex = EvalShadow_GetSplitIndex(context.shadowContext, _DirectionalShadowIndex, posInput.positionWS, alpha, cascadeCount);
            if (shadowSplitIndex >= 0)
            {
                SHADOW_TYPE shadow = 1.0;
                if (_DirectionalShadowIndex >= 0)
                {
                    DirectionalLightData light = _DirectionalLightData[_DirectionalShadowIndex];

#if defined(SCREEN_SPACE_SHADOWS_ON) && !defined(_SURFACE_TYPE_TRANSPARENT)
                    if ((light.screenSpaceShadowIndex & SCREEN_SPACE_SHADOW_INDEX_MASK) != INVALID_SCREEN_SPACE_SHADOW)
                    {
                        shadow = GetScreenSpaceColorShadow(posInput, light.screenSpaceShadowIndex).SHADOW_TYPE_SWIZZLE;
                    }
                    else
#endif
                    {
                        float3 L = -light.forward;
                        shadow = GetDirectionalShadowAttenuation(context.shadowContext,
                                                             posInput.positionSS, posInput.positionWS, GetNormalForShadowBias(bsdfData),
                                                             light.shadowIndex, L);
                    }
                }

                float3 cascadeShadowColor = lerp(s_CascadeColors[shadowSplitIndex], s_CascadeColors[shadowSplitIndex + 1], alpha);
                // We can't mix with the lighting as it can be HDR and it is hard to find a good lerp operation for this case that is still compliant with
                // exposure. So disable exposure instead and replace color.
                lightLoopOutput.diffuseLighting = cascadeShadowColor * Luminance(lightLoopOutput.diffuseLighting) * shadow;
            }

        }
    }
    else if (_DebugLightingMode == DEBUGLIGHTINGMODE_MATCAP_VIEW)
    {
        lightLoopOutput.specularLighting = float3(0.0, 0.0, 0.0);
        float3 normalVS = mul((float3x3)UNITY_MATRIX_V, bsdfData.normalWS).xyz;

        float3 V = GetWorldSpaceNormalizeViewDir(posInput.positionWS);
        float3 R = reflect(V, bsdfData.normalWS);

        float2 UV = saturate(normalVS.xy * 0.5f + 0.5f);

        float4 defaultColor = GetDiffuseOrDefaultColor(bsdfData, 1.0);

        if (defaultColor.a == 1.0)
        {
            UV = saturate(R.xy * 0.5f + 0.5f);
        }

        lightLoopOutput.diffuseLighting = SAMPLE_TEXTURE2D_LOD(_DebugMatCapTexture, s_linear_repeat_sampler, UV, 0).rgb * (_MatcapMixAlbedo > 0  ? defaultColor.rgb * _MatcapViewScale : 1.0f);

    #ifdef OUTPUT_SPLIT_LIGHTING // Work as matcap view is only call in forward, OUTPUT_SPLIT_LIGHTING isn't define in deferred.compute
        if (_EnableSubsurfaceScattering != 0 && ShouldOutputSplitLighting(bsdfData))
        {
            lightLoopOutput.specularLighting = lightLoopOutput.diffuseLighting;
        }
    #endif

    }
#endif
}

void LightLoop( float3 V, PositionInputs posInput, uint tile, uint zBin, PreLightData preLightData, BSDFData bsdfData, BuiltinData builtinData, uint featureFlags,
                out LightLoopOutput lightLoopOutput)
{
    // Init LightLoop output structure
    ZERO_INITIALIZE(LightLoopOutput, lightLoopOutput);

    LightLoopContext context;

    context.shadowContext    = InitShadowContext();
    context.shadowValue      = 1;
    context.sampleReflection = 0;

    // With XR single-pass and camera-relative: offset position to do lighting computations from the combined center view (original camera matrix).
    // This is required because there is only one list of lights generated on the CPU. Shadows are also generated once and shared between the instanced views.
    ApplyCameraRelativeXR(posInput.positionWS);

    // Initialize the contactShadow and contactShadowFade fields
    InitContactShadow(posInput, context);

    // First of all we compute the shadow value of the directional light to reduce the VGPR pressure
    if (featureFlags & LIGHTFEATUREFLAGS_DIRECTIONAL)
    {
        // Evaluate sun shadows.
        if (_DirectionalShadowIndex >= 0)
        {
            DirectionalLightData light = _DirectionalLightData[_DirectionalShadowIndex];

#if defined(SCREEN_SPACE_SHADOWS_ON) && !defined(_SURFACE_TYPE_TRANSPARENT)
            if ((light.screenSpaceShadowIndex & SCREEN_SPACE_SHADOW_INDEX_MASK) != INVALID_SCREEN_SPACE_SHADOW)
            {
                context.shadowValue = GetScreenSpaceColorShadow(posInput, light.screenSpaceShadowIndex).SHADOW_TYPE_SWIZZLE;
            }
            else
#endif
            {
                // TODO: this will cause us to load from the normal buffer first. Does this cause a performance problem?
                float3 L = -light.forward;

                // Is it worth sampling the shadow map?
                if ((light.lightDimmer > 0) && (light.shadowDimmer > 0) && // Note: Volumetric can have different dimmer, thus why we test it here
                    IsNonZeroBSDF(V, L, preLightData, bsdfData) &&
                    !ShouldEvaluateThickObjectTransmission(V, L, preLightData, bsdfData, light.shadowIndex))
                {
                    context.shadowValue = GetDirectionalShadowAttenuation(context.shadowContext,
                                                                          posInput.positionSS, posInput.positionWS, GetNormalForShadowBias(bsdfData),
                                                                          light.shadowIndex, L);
                }
            }
        }
    }

    uint i; // Declare once to avoid the D3D11 compiler warning.

    // This struct is define in the material. the Lightloop must not access it
    // PostEvaluateBSDF call at the end will convert Lighting to diffuse and specular lighting
    AggregateLighting aggregateLighting;
    ZERO_INITIALIZE(AggregateLighting, aggregateLighting); // LightLoop is in charge of initializing the struct

    if (featureFlags & LIGHTFEATUREFLAGS_PUNCTUAL)
    {
        EntityLookupParameters params = InitializePunctualLightLookup(tile, zBin);

        i = 0;

        LightData lightData;
        while (TryLoadPunctualLightData(i, params, lightData))
        {
            if (IsMatchingLightLayer(lightData.lightLayers, builtinData.renderingLayers))
            {
                DirectLighting lighting = EvaluateBSDF_Punctual(context, V, posInput, preLightData, lightData, bsdfData, builtinData);
                AccumulateDirectLighting(lighting, aggregateLighting);
            }

            i++;
        }
    }

    // Define macro for a better understanding of the loop
    // TODO: this code is now much harder to understand...
#define EVALUATE_BSDF_ENV_SKY(envLightData, TYPE, type) \
        IndirectLighting lighting = EvaluateBSDF_Env(context, V, posInput, preLightData, envLightData, bsdfData, envLightData.influenceShapeType, MERGE_NAME(GPUIMAGEBASEDLIGHTINGTYPE_, TYPE), MERGE_NAME(type, HierarchyWeight)); \
        AccumulateIndirectLighting(lighting, aggregateLighting);

// Environment cubemap test lightlayers, sky don't test it
#define EVALUATE_BSDF_ENV(envLightData, TYPE, type) if (IsMatchingLightLayer(envLightData.lightLayers, builtinData.renderingLayers)) { EVALUATE_BSDF_ENV_SKY(envLightData, TYPE, type) }

    // First loop iteration
    if (featureFlags & (LIGHTFEATUREFLAGS_ENV | LIGHTFEATUREFLAGS_SKY | LIGHTFEATUREFLAGS_SSREFRACTION | LIGHTFEATUREFLAGS_SSREFLECTION))
    {
        float reflectionHierarchyWeight = 0.0; // Max: 1.0
        float refractionHierarchyWeight = _EnableSSRefraction ? 0.0 : 1.0; // Max: 1.0

        // Reflection / Refraction hierarchy is
        //  1. Screen Space Refraction / Reflection
        //  2. Environment Reflection / Refraction
        //  3. Sky Reflection / Refraction

        // Apply SSR.
    #if (defined(_SURFACE_TYPE_TRANSPARENT) && !defined(_DISABLE_SSR_TRANSPARENT)) || (!defined(_SURFACE_TYPE_TRANSPARENT) && !defined(_DISABLE_SSR))
        {
            IndirectLighting indirect = EvaluateBSDF_ScreenSpaceReflection(posInput, preLightData, bsdfData,
                                                                           reflectionHierarchyWeight);
            AccumulateIndirectLighting(indirect, aggregateLighting);
        }
    #endif

        EntityLookupParameters params = InitializeReflectionProbeLookup(tile, zBin);
        i = 0;
        EnvLightData envLightData;
        uint         envLightIndex;
        if(!TryLoadReflectionProbeData(i, params, envLightData, envLightIndex))
        {
            envLightData = InitSkyEnvLightData(0);
        }

        if ((featureFlags & LIGHTFEATUREFLAGS_SSREFRACTION) && (_EnableSSRefraction > 0))
        {
            IndirectLighting lighting = EvaluateBSDF_ScreenspaceRefraction(context, V, posInput, preLightData, bsdfData, envLightData, refractionHierarchyWeight);
            AccumulateIndirectLighting(lighting, aggregateLighting);
        }

        // Reflection probes are sorted by volume (in the increasing order).
        if (featureFlags & LIGHTFEATUREFLAGS_ENV)
        {
            params = InitializeReflectionProbeLookup(tile, zBin);
            context.sampleReflection = SINGLE_PASS_CONTEXT_SAMPLE_REFLECTION_PROBES;

            while (TryLoadReflectionProbeData(i, params, envLightData, envLightIndex))
            {
                envLightData = LoadReflectionProbeDataUnsafe(envLightIndex);

                if (reflectionHierarchyWeight < 1.0)
                {
                    EVALUATE_BSDF_ENV(envLightData, REFLECTION, reflection);
                }
                // Refraction probe and reflection probe will process exactly the same weight. It will be good for performance to be able to share this computation
                // However it is hard to deal with the fact that reflectionHierarchyWeight and refractionHierarchyWeight have not the same values, they are independent
                // The refraction probe is rarely used and happen only with sphere shape and high IOR. So we accept the slow path that use more simple code and
                // doesn't affect the performance of the reflection which is more important.
                // We reuse LIGHTFEATUREFLAGS_SSREFRACTION flag as refraction is mainly base on the screen. Would be a waste to not use screen and only cubemap.
                if ((featureFlags & LIGHTFEATUREFLAGS_SSREFRACTION) && (refractionHierarchyWeight < 1.0))
                {
                    EVALUATE_BSDF_ENV(envLightData, REFRACTION, refraction);
                }
                i++;
            }
        }

        // Only apply the sky IBL if the sky texture is available
        if ((featureFlags & LIGHTFEATUREFLAGS_SKY) && _EnvLightSkyEnabled)
        {
            // The sky is a single cubemap texture separate from the reflection probe texture array (different resolution and compression)
            context.sampleReflection = SINGLE_PASS_CONTEXT_SAMPLE_SKY;

            // The sky data are generated on the fly so the compiler can optimize the code
            EnvLightData envLightSky = InitSkyEnvLightData(0);

            // Only apply the sky if we haven't yet accumulated enough IBL lighting.
            if (reflectionHierarchyWeight < 1.0)
            {
                EVALUATE_BSDF_ENV_SKY(envLightSky, REFLECTION, reflection);
            }

            if ((featureFlags & LIGHTFEATUREFLAGS_SSREFRACTION) && (refractionHierarchyWeight < 1.0))
            {
                EVALUATE_BSDF_ENV_SKY(envLightSky, REFRACTION, refraction);
            }
        }
    }
#undef EVALUATE_BSDF_ENV
#undef EVALUATE_BSDF_ENV_SKY

    if (featureFlags & LIGHTFEATUREFLAGS_DIRECTIONAL)
    {
        for (i = 0; i < _DirectionalLightCount; ++i)
        {
            if (IsMatchingLightLayer(_DirectionalLightData[i].lightLayers, builtinData.renderingLayers))
            {
                DirectLighting lighting = EvaluateBSDF_Directional(context, V, posInput, preLightData, _DirectionalLightData[i], bsdfData, builtinData);
                AccumulateDirectLighting(lighting, aggregateLighting);
            }
        }
    }

#if SHADEROPTIONS_AREA_LIGHTS
    if (featureFlags & LIGHTFEATUREFLAGS_AREA)
    {
        EntityLookupParameters params = InitializeAreaLightLookup(tile, zBin);

        i = 0;

        LightData lightData;
        while (TryLoadAreaLightData(i, params, lightData))
        {
            if (IsMatchingLightLayer(lightData.lightLayers, builtinData.renderingLayers))
            {
                DirectLighting lighting = EvaluateBSDF_Area(context, V, posInput, preLightData, lightData, bsdfData, builtinData);
                AccumulateDirectLighting(lighting, aggregateLighting);
            }

            i++;
        }
    }
#endif

#if defined(PROBE_VOLUMES_L1) || defined(PROBE_VOLUMES_L2)
    bool uninitializedGI = IsUninitializedGI(builtinData.bakeDiffuseLighting);
    // If probe volume feature is enabled, this bit is enabled for all tiles to handle ambient probe fallback.
    // Even so, the bound resources might be invalid in some cases, so we still need to check on _EnableProbeVolumes.
    bool apvEnabled = (featureFlags & LIGHTFEATUREFLAGS_PROBE_VOLUME) && _EnableProbeVolumes;
    if (!apvEnabled)
    {
        builtinData.bakeDiffuseLighting = (uninitializedGI && !apvEnabled) ? float3(0.0, 0.0, 0.0) : builtinData.bakeDiffuseLighting;
        builtinData.backBakeDiffuseLighting = (uninitializedGI && !apvEnabled) ? float3(0.0, 0.0, 0.0) : builtinData.backBakeDiffuseLighting;
    }

    if (apvEnabled)
    {
        if (uninitializedGI)
        {
            // Need to make sure not to apply ModifyBakedDiffuseLighting() twice to our bakeDiffuseLighting data, which could happen if we are dealing with initialized data (light maps).
            // Create a local BuiltinData variable here, and then add results to builtinData.bakeDiffuseLighting at the end.
            BuiltinData apvBuiltinData;
            ZERO_INITIALIZE(BuiltinData, apvBuiltinData);
            SetAsUninitializedGI(apvBuiltinData.bakeDiffuseLighting);
            SetAsUninitializedGI(apvBuiltinData.backBakeDiffuseLighting);

            EvaluateAdaptiveProbeVolume(GetAbsolutePositionWS(posInput.positionWS),
                                        bsdfData.normalWS,
                                        -bsdfData.normalWS,
                                        apvBuiltinData.bakeDiffuseLighting,
                                        apvBuiltinData.backBakeDiffuseLighting);

            float indirectDiffuseMultiplier = GetIndirectDiffuseMultiplier(builtinData.renderingLayers);
            apvBuiltinData.bakeDiffuseLighting *= indirectDiffuseMultiplier;
            apvBuiltinData.backBakeDiffuseLighting *= indirectDiffuseMultiplier;

#ifdef MODIFY_BAKED_DIFFUSE_LIGHTING
#ifdef DEBUG_DISPLAY
            // When the lux meter is enabled, we don't want the albedo of the material to modify the diffuse baked lighting
            if (_DebugLightingMode != DEBUGLIGHTINGMODE_LUX_METER)
#endif
                ModifyBakedDiffuseLighting(V, posInput, preLightData, bsdfData, apvBuiltinData);

#endif

            #if (SHADERPASS == SHADERPASS_DEFERRED_LIGHTING)
            // If we are deferred we should apply baked AO here as it was already apply for lightmap.
            // When using probe volumes for the pixel (i.e. we have uninitialized GI), we include the surfaceData.ambientOcclusion as
            // payload information alongside the un-init flag.
            // It should not be applied in forward as in this case the baked AO is correctly apply in PostBSDF()
            // This is applied only on bakeDiffuseLighting as ModifyBakedDiffuseLighting combine both bakeDiffuseLighting and backBakeDiffuseLighting
            float surfaceDataAO = ExtractPayloadFromUninitializedGI(builtinData.bakeDiffuseLighting);
            apvBuiltinData.bakeDiffuseLighting *= surfaceDataAO;
            #endif

            ApplyDebugToBuiltinData(apvBuiltinData);

            builtinData.bakeDiffuseLighting = uninitializedGI ? float3(0.0, 0.0, 0.0) : builtinData.bakeDiffuseLighting;
            // Note: builtinDataProbeVolumes.bakeDiffuseLighting and builtinDataProbeVolumes.backBakeDiffuseLighting were combine inside of ModifyBakedDiffuseLighting().
            builtinData.bakeDiffuseLighting += apvBuiltinData.bakeDiffuseLighting;
        }
    }
#endif

#if !defined(_SURFACE_TYPE_TRANSPARENT)
    // If we use the texture ssgi for ssgi or rtgi, we want to combine it with the value in the bake diffuse lighting value
    if (_IndirectDiffuseMode != INDIRECTDIFFUSEMODE_OFF)
    {
        BuiltinData builtinDataSSGI;
        ZERO_INITIALIZE(BuiltinData, builtinDataSSGI);
        builtinDataSSGI.bakeDiffuseLighting = LOAD_TEXTURE2D_X(_IndirectDiffuseTexture, posInput.positionSS).xyz * GetInverseCurrentExposureMultiplier();
        builtinDataSSGI.bakeDiffuseLighting *= GetIndirectDiffuseMultiplier(builtinData.renderingLayers);

        // TODO: try to see if we can share code with probe volume
#ifdef MODIFY_BAKED_DIFFUSE_LIGHTING
#ifdef DEBUG_DISPLAY
        // When the lux meter is enabled, we don't want the albedo of the material to modify the diffuse baked lighting
        if (_DebugLightingMode != DEBUGLIGHTINGMODE_LUX_METER)
#endif
            ModifyBakedDiffuseLighting(V, posInput, preLightData, bsdfData, builtinDataSSGI);

#endif
        // In the alpha channel, we have the interpolation value that we use to blend the result of SSGI/RTGI with the other GI thechnique
        builtinData.bakeDiffuseLighting = lerp(builtinData.bakeDiffuseLighting,
                                            builtinDataSSGI.bakeDiffuseLighting,
                                            LOAD_TEXTURE2D_X(_IndirectDiffuseTexture, posInput.positionSS).w);
    }
#endif

    ApplyDebugToLighting(context, builtinData, aggregateLighting);

    // Note: We can't apply the IndirectDiffuseMultiplier here as with GBuffer, Emissive is part of the bakeDiffuseLighting.
    // so IndirectDiffuseMultiplier is apply in PostInitBuiltinData or related location (like for probe volume)
    aggregateLighting.indirect.specularReflected *= GetIndirectSpecularMultiplier(builtinData.renderingLayers);

    // Also Apply indiret diffuse (GI)
    // PostEvaluateBSDF will perform any operation wanted by the material and sum everything into diffuseLighting and specularLighting
    PostEvaluateBSDF(   context, V, posInput, preLightData, bsdfData, builtinData, aggregateLighting, lightLoopOutput);

    ApplyDebug(context, posInput, bsdfData, lightLoopOutput);
}

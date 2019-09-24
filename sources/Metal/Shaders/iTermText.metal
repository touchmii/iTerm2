#import "iTermTextShaderCommon.h"
#import <metal_math>

static float4 iTermAlphaVectorForTextColor(float4 textColor) {
    constexpr float4 blackVector = float4(0, 0, 1, 0);
    constexpr float4 redVector = float4(0, 1, 0, 0);
    constexpr float4 greenVector = float4(1, 0, 0, 0);
    constexpr float4 yellowVector = float4(0, 0, 0, 1);

    // Low thresholds bias toward heavier text for mid-tones.
    constexpr float threshold = 0.6;

    // https://gitlab.com/gnachman/iterm2/wikis/macOS-Mojave-Regression-Challenge
    if (textColor.x + textColor.y > threshold * 2) {
        return yellowVector;
    } else if (textColor.y > threshold) {
        return greenVector;
    } else if (textColor.x > threshold) {
        return redVector;
    } else {
        return blackVector;
    }
}

// Slow path: taken for all underlined code paths and all solid background code paths (because they aren't used
// and I don't want to spend time testing dead code right now).
vertex iTermTextVertexFunctionOutput
iTermTextVertexShader(uint vertexID [[ vertex_id ]],
                      constant float2 *offset [[ buffer(iTermVertexInputIndexOffset) ]],
                      constant iTermVertex *vertexArray [[ buffer(iTermVertexInputIndexVertices) ]],
                      constant vector_uint2 *viewportSizePointer  [[ buffer(iTermVertexInputIndexViewportSize) ]],
                      constant iTermVertexInputMojaveVertexTextInfoStruct *textInfo  [[ buffer(iTermVertexInputMojaveVertexTextInfo) ]],
                      device iTermTextPIU *perInstanceUniforms [[ buffer(iTermVertexInputIndexPerInstanceUniforms) ]],
                      unsigned int iid [[instance_id]]) {
    iTermTextVertexFunctionOutput out;

    // pixelSpacePosition is in pixels
    float2 pixelSpacePosition = vertexArray[vertexID].position.xy + perInstanceUniforms[iid].offset.xy + offset[0];
    float2 viewportSize = float2(*viewportSizePointer);

    out.clipSpacePosition.xy = pixelSpacePosition / viewportSize;
    out.clipSpacePosition.z = 0.0;
    out.clipSpacePosition.w = 1;
    out.backgroundTextureCoordinate = pixelSpacePosition / viewportSize;
    out.backgroundTextureCoordinate.y = 1 - out.backgroundTextureCoordinate.y;
    out.textureOffset = perInstanceUniforms[iid].textureOffset;
    out.textureCoordinate = vertexArray[vertexID].textureCoordinate + perInstanceUniforms[iid].textureOffset;
    out.textColor = perInstanceUniforms[iid].textColor;
    out.backgroundColor = perInstanceUniforms[iid].backgroundColor;
    out.colorModelIndex = perInstanceUniforms[iid].colorModelIndex;
    out.viewportSize = viewportSize;

    out.cellOffset = perInstanceUniforms[iid].offset.xy + offset[0];
    out.underlineStyle = perInstanceUniforms[iid].underlineStyle;
    out.underlineColor = perInstanceUniforms[iid].underlineColor;
    out.alphaVector = iTermAlphaVectorForTextColor(out.textColor);
    return out;
}

vertex iTermTextVertexFunctionOutputEmoji
iTermTextVertexShaderEmoji(uint vertexID [[ vertex_id ]],
                           constant float2 *offset [[ buffer(iTermVertexInputIndexOffset) ]],
                           constant iTermVertex *vertexArray [[ buffer(iTermVertexInputIndexVertices) ]],
                           constant vector_uint2 *viewportSizePointer  [[ buffer(iTermVertexInputIndexViewportSize) ]],
                           device iTermTextPIU *perInstanceUniforms [[ buffer(iTermVertexInputIndexPerInstanceUniforms) ]],
                           unsigned int iid [[instance_id]]) {
    iTermTextVertexFunctionOutputEmoji out;

    // pixelSpacePosition is in pixels
    float2 pixelSpacePosition = vertexArray[vertexID].position.xy + perInstanceUniforms[iid].offset.xy + offset[0];
    float2 viewportSize = float2(*viewportSizePointer);

    out.clipSpacePosition.xy = pixelSpacePosition / viewportSize;
    out.clipSpacePosition.z = 0.0;
    out.clipSpacePosition.w = 1;

    out.textureCoordinate = vertexArray[vertexID].textureCoordinate + perInstanceUniforms[iid].textureOffset;

    return out;
}

// Not emoji, not underlined, not using the solid background color optimization, not macOS 10.14
vertex iTermTextVertexFunctionOutputBlending
iTermTextVertexShaderBlending(uint vertexID [[ vertex_id ]],
                              constant float2 *offset [[ buffer(iTermVertexInputIndexOffset) ]],
                              constant iTermVertex *vertexArray [[ buffer(iTermVertexInputIndexVertices) ]],
                              constant vector_uint2 *viewportSizePointer  [[ buffer(iTermVertexInputIndexViewportSize) ]],
                              device iTermTextPIU *perInstanceUniforms [[ buffer(iTermVertexInputIndexPerInstanceUniforms) ]],
                              unsigned int iid [[instance_id]]) {
    iTermTextVertexFunctionOutputBlending out;

    // pixelSpacePosition is in pixels
    float2 pixelSpacePosition = vertexArray[vertexID].position.xy + perInstanceUniforms[iid].offset.xy + offset[0];
    float2 viewportSize = float2(*viewportSizePointer);

    out.clipSpacePosition.xy = pixelSpacePosition / viewportSize;
    out.clipSpacePosition.z = 0.0;
    out.clipSpacePosition.w = 1;

    out.textureCoordinate = vertexArray[vertexID].textureCoordinate + perInstanceUniforms[iid].textureOffset;
    out.backgroundTextureCoordinate = pixelSpacePosition / viewportSize;
    out.backgroundTextureCoordinate.y = 1 - out.backgroundTextureCoordinate.y;
    out.textColor = perInstanceUniforms[iid].textColor;

    return out;
}


// Not emoji, not underlined, macOS 10.14 (no subpixel AA support)
vertex iTermTextVertexFunctionOutputMonochrome
iTermTextVertexShaderMonochrome(uint vertexID [[ vertex_id ]],
                                constant float2 *offset [[ buffer(iTermVertexInputIndexOffset) ]],
                                constant iTermVertex *vertexArray [[ buffer(iTermVertexInputIndexVertices) ]],
                                constant vector_uint2 *viewportSizePointer  [[ buffer(iTermVertexInputIndexViewportSize) ]],
                                constant iTermVertexInputMojaveVertexTextInfoStruct *textInfo [[ buffer(iTermVertexInputMojaveVertexTextInfo) ]],
                                device iTermTextPIU *perInstanceUniforms [[ buffer(iTermVertexInputIndexPerInstanceUniforms) ]],
                                unsigned int iid [[instance_id]]) {
    iTermTextVertexFunctionOutputMonochrome out;

    // pixelSpacePosition is in pixels
    float2 pixelSpacePosition = vertexArray[vertexID].position.xy + perInstanceUniforms[iid].offset.xy + offset[0];
    float2 viewportSize = float2(*viewportSizePointer);

    out.clipSpacePosition.xy = pixelSpacePosition / viewportSize;
    out.clipSpacePosition.z = 0.0;
    out.clipSpacePosition.w = 1;

    out.textureCoordinate = vertexArray[vertexID].textureCoordinate + perInstanceUniforms[iid].textureOffset;
    out.textColor = perInstanceUniforms[iid].textColor;
    out.alphaVector = iTermAlphaVectorForTextColor(out.textColor);

    return out;
}

// The underlining fragment shaders are separate from the non-underlining ones
// because of an apparent compiler bug. See issue 6779.

#pragma mark - Fragment Shaders

// "Blending" is slower but can deal with any combination of foreground/background
// color components. It's used when there's a background image, a badge,
// broadcast image stripes, or anything else nontrivial behind the text.

// This function is shared by blending and monochrome because Emoji without underline doesn't take the background color into account.
fragment float4
iTermTextFragmentShaderWithBlendingEmoji(iTermTextVertexFunctionOutputEmoji in [[stage_in]],
                                         texture2d<float> texture [[ texture(iTermTextureIndexPrimary) ]],
                                         texture2d<float> drawable [[ texture(iTermTextureIndexBackground) ]],
                                         texture2d<float> colorModels [[ texture(iTermTextureIndexSubpixelModels) ]],
                                         constant iTermTextureDimensions *dimensions  [[ buffer(iTermFragmentInputIndexTextureDimensions) ]]) {
    constexpr sampler textureSampler(mag_filter::linear,
                                     min_filter::linear);

    return texture.sample(textureSampler, in.textureCoordinate);
}

fragment float4
iTermTextFragmentShaderWithBlending(iTermTextVertexFunctionOutputBlending in [[stage_in]],
                                    texture2d<float> texture [[ texture(iTermTextureIndexPrimary) ]],
                                    texture2d<float> drawable [[ texture(iTermTextureIndexBackground) ]],
                                    texture2d<float> colorModels [[ texture(iTermTextureIndexSubpixelModels) ]],
                                    constant iTermTextureDimensions *dimensions  [[ buffer(iTermFragmentInputIndexTextureDimensions) ]]) {
    constexpr sampler textureSampler(mag_filter::linear,
                                     min_filter::linear);

    float4 bwColor = texture.sample(textureSampler, in.textureCoordinate);
    const float4 backgroundColor = drawable.sample(textureSampler, in.backgroundTextureCoordinate);

    // Not emoji, not underlined.
    if (bwColor.x == 1 && bwColor.y == 1 && bwColor.z == 1) {
        discard_fragment();
    }

    return RemapColor(in.textColor * 17.0, backgroundColor, bwColor, colorModels);
}

fragment float4
iTermTextFragmentShaderWithBlendingUnderlinedEmoji(iTermTextVertexFunctionOutput in [[stage_in]],
                                                   texture2d<float> texture [[ texture(iTermTextureIndexPrimary) ]],
                                                   texture2d<float> drawable [[ texture(iTermTextureIndexBackground) ]],
                                                   texture2d<float> colorModels [[ texture(iTermTextureIndexSubpixelModels) ]],
                                                   constant iTermTextureDimensions *dimensions  [[ buffer(iTermFragmentInputIndexTextureDimensions) ]]) {
    constexpr sampler textureSampler(mag_filter::linear,
                                     min_filter::linear);

    float4 bwColor = texture.sample(textureSampler, in.textureCoordinate);

    float strikethroughWeight = 0;
    if (in.underlineStyle & iTermMetalGlyphAttributesUnderlineStrikethroughFlag) {
        strikethroughWeight = ComputeWeightOfUnderlineRegular(iTermMetalGlyphAttributesUnderlineStrikethrough,
                                                              in.clipSpacePosition.xy,
                                                              in.viewportSize,
                                                              in.cellOffset,
                                                              dimensions->strikethroughOffset,
                                                              dimensions->strikethroughThickness,
                                                              dimensions->textureSize,
                                                              in.textureOffset,
                                                              in.textureCoordinate,
                                                              dimensions->glyphSize,
                                                              dimensions->cellSize,
                                                              texture,
                                                              textureSampler,
                                                              dimensions->scale);
    }

    // Underlined emoji code path
    const float underlineWeight = ComputeWeightOfUnderlineRegular((in.underlineStyle & iTermMetalGlyphAttributesUnderlineBitmask),
                                                                 in.clipSpacePosition.xy,
                                                                 in.viewportSize,
                                                                 in.cellOffset,
                                                                 dimensions->underlineOffset,
                                                                 dimensions->underlineThickness,
                                                                 dimensions->textureSize,
                                                                 in.textureOffset,
                                                                 in.textureCoordinate,
                                                                 dimensions->glyphSize,
                                                                 dimensions->cellSize,
                                                                 texture,
                                                                 textureSampler,
                                                                 dimensions->scale);
    return mix(bwColor,
               in.underlineColor,
               max(strikethroughWeight, underlineWeight));
}

fragment float4
iTermTextFragmentShaderWithBlendingUnderlined(iTermTextVertexFunctionOutput in [[stage_in]],
                                              texture2d<float> texture [[ texture(iTermTextureIndexPrimary) ]],
                                              texture2d<float> drawable [[ texture(iTermTextureIndexBackground) ]],
                                              texture2d<float> colorModels [[ texture(iTermTextureIndexSubpixelModels) ]],
                                              constant iTermTextureDimensions *dimensions  [[ buffer(iTermFragmentInputIndexTextureDimensions) ]]) {
    constexpr sampler textureSampler(mag_filter::linear,
                                     min_filter::linear);

    float4 bwColor = texture.sample(textureSampler, in.textureCoordinate);
    const float4 backgroundColor = drawable.sample(textureSampler, in.backgroundTextureCoordinate);

    // Underlined not emoji.
    const float underlineWeight = ComputeWeightOfUnderlineInverted(in.underlineStyle,
                                                                  in.clipSpacePosition.xy,
                                                                  in.viewportSize,
                                                                  in.cellOffset,
                                                                  dimensions->underlineOffset,
                                                                  dimensions->underlineThickness,
                                                                  dimensions->strikethroughOffset,
                                                                  dimensions->strikethroughThickness,
                                                                  dimensions->textureSize,
                                                                  in.textureOffset,
                                                                  in.textureCoordinate,
                                                                  dimensions->glyphSize,
                                                                  dimensions->cellSize,
                                                                  texture,
                                                                  textureSampler,
                                                                  dimensions->scale);
    if (underlineWeight == 0 && bwColor.x == 1 && bwColor.y == 1 && bwColor.z == 1) {
        discard_fragment();
    }

    float4 textColor = RemapColor(in.textColor * 17.0, backgroundColor, bwColor, colorModels);
    return mix(textColor, in.underlineColor, underlineWeight);
}

#pragma mark - Monochrome
// macOS 10.14+ code path (no subpixel AA support)

// Color and return sample from texture
fragment float4
iTermTextFragmentShaderMonochrome(iTermTextVertexFunctionOutputMonochrome in [[stage_in]],
                                  texture2d<float> texture [[ texture(iTermTextureIndexPrimary) ]],
                                  texture2d<float> drawable [[ texture(iTermTextureIndexBackground) ]],
                                  constant iTermTextureDimensions *dimensions  [[ buffer(iTermFragmentInputIndexTextureDimensions) ]]) {
    constexpr sampler textureSampler(mag_filter::linear,
                                     min_filter::linear);

    float4 textureColor = texture.sample(textureSampler, in.textureCoordinate);
    float4 result = in.textColor;
    result.w = dot(textureColor, in.alphaVector);
    result.xyz *= result.w;
    return result;
}

// Return sample from texture plus underline
fragment float4
iTermTextFragmentShaderMonochromeUnderlinedEmoji(iTermTextVertexFunctionOutput in [[stage_in]],
                                                 texture2d<float> texture [[ texture(iTermTextureIndexPrimary) ]],
                                                 texture2d<float> drawable [[ texture(iTermTextureIndexBackground) ]],
                                                 constant iTermTextureDimensions *dimensions  [[ buffer(iTermFragmentInputIndexTextureDimensions) ]]) {
    constexpr sampler textureSampler(mag_filter::linear,
                                     min_filter::linear);

    float4 textureColor = texture.sample(textureSampler, in.textureCoordinate);

    float strikethroughWeight = 0;
    if (in.underlineStyle & iTermMetalGlyphAttributesUnderlineStrikethroughFlag) {
        strikethroughWeight = ComputeWeightOfUnderlineRegular(iTermMetalGlyphAttributesUnderlineStrikethrough,
                                                              in.clipSpacePosition.xy,
                                                              in.viewportSize,
                                                              in.cellOffset,
                                                              dimensions->strikethroughOffset,
                                                              dimensions->strikethroughThickness,
                                                              dimensions->textureSize,
                                                              in.textureOffset,
                                                              in.textureCoordinate,
                                                              dimensions->glyphSize,
                                                              dimensions->cellSize,
                                                              texture,
                                                              textureSampler,
                                                              dimensions->scale);
    }

    // Underlined emoji code path
    const float underlineWeight = ComputeWeightOfUnderlineRegular((in.underlineStyle & iTermMetalGlyphAttributesUnderlineBitmask),
                                                                 in.clipSpacePosition.xy,
                                                                 in.viewportSize,
                                                                 in.cellOffset,
                                                                 dimensions->underlineOffset,
                                                                 dimensions->underlineThickness,
                                                                 dimensions->textureSize,
                                                                 in.textureOffset,
                                                                 in.textureCoordinate,
                                                                 dimensions->glyphSize,
                                                                 dimensions->cellSize,
                                                                 texture,
                                                                 textureSampler,
                                                                 dimensions->scale);
    float4 result = mix(textureColor,
                       in.underlineColor,
                       max(strikethroughWeight, underlineWeight));
    result.xyz *= result.w;
    return result;
}

// Return colored sample from texture plus underline
fragment float4
iTermTextFragmentShaderMonochromeUnderlined(iTermTextVertexFunctionOutput in [[stage_in]],
                                            texture2d<float> texture [[ texture(iTermTextureIndexPrimary) ]],
                                            texture2d<float> drawable [[ texture(iTermTextureIndexBackground) ]],
                                            constant iTermTextureDimensions *dimensions  [[ buffer(iTermFragmentInputIndexTextureDimensions) ]]) {
    constexpr sampler textureSampler(mag_filter::linear,
                                     min_filter::linear);

    float4 textureColor = texture.sample(textureSampler, in.textureCoordinate);

    float strikethroughWeight = 0;
    if (in.underlineStyle & iTermMetalGlyphAttributesUnderlineStrikethroughFlag) {
        strikethroughWeight = ComputeWeightOfUnderlineRegular(iTermMetalGlyphAttributesUnderlineStrikethrough,
                                                              in.clipSpacePosition.xy,
                                                              in.viewportSize,
                                                              in.cellOffset,
                                                              dimensions->strikethroughOffset,
                                                              dimensions->strikethroughThickness,
                                                              dimensions->textureSize,
                                                              in.textureOffset,
                                                              in.textureCoordinate,
                                                              dimensions->glyphSize,
                                                              dimensions->cellSize,
                                                              texture,
                                                              textureSampler,
                                                              dimensions->scale);
    }
    // Underlined not emoji.
    const float underlineWeight = ComputeWeightOfUnderlineRegular((in.underlineStyle & iTermMetalGlyphAttributesUnderlineBitmask),
                                                                 in.clipSpacePosition.xy,
                                                                 in.viewportSize,
                                                                 in.cellOffset,
                                                                 dimensions->underlineOffset,
                                                                 dimensions->underlineThickness,
                                                                 dimensions->textureSize,
                                                                 in.textureOffset,
                                                                 in.textureCoordinate,
                                                                 dimensions->glyphSize,
                                                                 dimensions->cellSize,
                                                                 texture,
                                                                 textureSampler,
                                                                 dimensions->scale);

    float4 recoloredTextColor = in.textColor;
    recoloredTextColor.w = dot(textureColor, in.alphaVector);

    float4 result = mix(recoloredTextColor,
                       in.underlineColor,
                       max(strikethroughWeight, underlineWeight));
    result.xyz *= result.w;
    return result;
}

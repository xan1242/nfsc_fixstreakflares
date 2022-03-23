#ifndef GLOBAL_H
#define GLOBAL_H

//#include "registermap.h"

// Defined out for the Xbox360 - only needed on the PC
#define DECLARE_TEXTURE(textured)	shared texture textured : textured;
#define ASSIGN_TEXTURE(textured)	Texture = <textured>;
#define DECLARE_MINFILTER(default_filter)			 MINFILTER = default_filter;
#define DECLARE_MAGFILTER(default_filter)			 MAGFILTER = default_filter;
#define DECLARE_MIPFILTER(default_filter)			 MIPFILTER = default_filter;
#define COMPILETIME_BOOL bool
#define cmWorldViewProj WorldViewProj
//#define DIFFUSE_SAMPLER DIFFUSEMAP_SAMPLER

/////////////////////////////////////////////////////////////////////////////////////////
float4x4	cmWorldViewProj			: WorldViewProj; //WORLDVIEWPROJECTION ;
//float4x4	WorldViewProj : REG_cmWorldViewProj; //WORLDVIEWPROJECTION ;
float4		cvScreenOffset			: cvScreenOffset; //SCREENOFFSET;
float4		cvVertexPowerBrightness : cvVertexPowerBrightness;

float4 world_position( float4 screen_pos )
{
    float4 p = mul(screen_pos, cmWorldViewProj);  
    p.xy += cvScreenOffset.xy * p.w;
    return p;
}

float4 screen_position( float4 screen_pos )
{
    screen_pos.xy += cvScreenOffset.xy;
    return screen_pos;
}

float4 CalcVertexColour(float4 colour)
{
    float4 result = pow(colour, cvVertexPowerBrightness.x) * cvVertexPowerBrightness.y;
    result.w = colour.w;
    return result;
}

float3 ScaleHeadLightIntensity(float3 colour) 
{
    float3 result = colour * cvVertexPowerBrightness.z;
    return result;
}



/////////////////////////////////////////////////////////////////////////////////////////
// HDR Colour Space compression
//
// Convert to a log or psudeo-log colour space to save high dynamic range data
/////////////////////////////////////////////////////////////////////////////////////////
#define kCompressCoeff ( 1.0f )
float3 CompressColourSpace(float3 colour)
{
    return colour / (kCompressCoeff+colour);
}

float3 DeCompressColourSpace(float3 colour)
{
    float3 clr = max( 0.01, kCompressCoeff-colour );
    return colour / clr;
}


/////////////////////////////////////////////////////////////////////////////////////////
// RGBE8 Encoding/Decoding
// The RGBE8 format stores a mantissa per color channel and a shared exponent 
// stored in alpha. Since the exponent is shared, it's computed based on the
// highest intensity color component. The resulting color is RGB * 2^Alpha,
// which scales the data across a logarithmic scale.
/////////////////////////////////////////////////////////////////////////////////////////

float4 EncodeRGBE8( in float3 rgb )	  
{
    float4 vEncoded;

    // Determine the largest color component
    float maxComponent = max( max(rgb.r, rgb.g), rgb.b );
    
    // Round to the nearest integer exponent
    float fExp = ceil( log2(maxComponent) );

    // Divide the components by the shared exponent
    vEncoded.rgb = rgb / exp2(fExp);
    
    // Store the shared exponent in the alpha channel
    vEncoded.a = (fExp + 128) / 255;

    return vEncoded;
}

/////////////////////////////////////////////////////////////////////////////////////////

float3 DecodeRGBE8( in float4 rgbe )
{
    float3 vDecoded;

    // Retrieve the shared exponent
    float fExp = rgbe.a * 255 - 128;
    
    // Multiply through the color components
    vDecoded = rgbe.rgb * exp2(fExp);
    
    return vDecoded;
}

/////////////////////////////////////////////////////////////////////////////////////////
#endif

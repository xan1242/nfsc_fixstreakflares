//
// Standard Effect
//
#include "global.h"

shared float4x4 cmWorldView			: REG_cmWorldView; //WORLDVIEW
shared float4x4 cmWorldMat			: REG_cmWorldMat;  //local to world matrix
shared float3	cvLocalEyePos		: REG_cvLocalEyePos; //LOCALEYEPOS;
shared float4	cvTextureOffset		: REG_cvTextureOffset; //TEXTUREANIMOFFSET;


shared float cfBrightness			: REG_cfBrightness; //STANDARD_BRIGHTNESS
shared float4 cvLocalCenter			: REG_cvLocalCenter; //LOCALCENTER;
shared float4 cvBaseAlphaRef		: REG_cvBaseAlphaRef; //BASEALPHAREF;
shared float4 cvBlurParams			: REG_cvBlurParams; //IS_MOTIONBLUR_VIGNETTED;
shared float4 cmPrevWorldViewProj		: REG_cmPrevWorldViewProj; //BASEALPHAREF;
//shared float4 cfSplitScreenUVScale	: REG_cfSplitScreenUVScale; // PC edit - no splitscreen yet
shared float  cfMipMapBias			: REG_cfMipMapBias;
shared float4 cvFogColour           : REG_cvFogColour;


static const float FuzzWidth = 0.15f;//0.05f;//changed from 0.05 to 0.15 by Lee Rosenbaum Aug 23, 2006;

static const float MaxParticleSize = 0.75f;
static const float MaterialShininess = 10;

// Pro-Street these should not change much at all (its the sun)
//float4	cvLightColour;			
float4	cavLightColours[10] : cavLightColours;// PC / Carbon edit - it uses arrays
//float4	cvLightPosition;
float4	cavLightPositions[10] : cavLightPositions;

// these should be artist controlled
float3 ambient_colour = float3(0.72,0.8,0.9); // PC edit - PC version has it in a variable, not a static definition...
//#define ambient_colour ( float3(0.72,0.8,0.9) )

float magnitude_debug = 1.0;

DECLARE_TEXTURE(MISCMAP1_TEXTURE)
sampler MISCMAP1_SAMPLER = sampler_state	// backbuffer for screen distortion
{
	ASSIGN_TEXTURE(MISCMAP1_TEXTURE)
	AddressU = CLAMP;
	AddressV = CLAMP;
	DECLARE_MIPFILTER(LINEAR)
	DECLARE_MINFILTER(LINEAR)
	DECLARE_MAGFILTER(LINEAR)
};

DECLARE_TEXTURE(OPACITYMAP_TEXTURE)
sampler OPACITY_SAMPLER = sampler_state	// rain alpha texture
{
	ASSIGN_TEXTURE(OPACITYMAP_TEXTURE)
	AddressU = CLAMP;
	AddressV = CLAMP;
	DECLARE_MIPFILTER(LINEAR)
	DECLARE_MINFILTER(LINEAR)
	DECLARE_MAGFILTER(LINEAR)
};
DECLARE_TEXTURE(DIFFUSEMAP_TEXTURE) // PC edit - these NEED to be here for the shader to work!
sampler DIFFUSE_SAMPLER = sampler_state
{
	ASSIGN_TEXTURE(DIFFUSEMAP_TEXTURE)
	AddressU = WRAP;
	AddressV = WRAP;
	DECLARE_MIPFILTER(LINEAR)
	DECLARE_MINFILTER(LINEAR)
	DECLARE_MAGFILTER(LINEAR)
};

DECLARE_TEXTURE(NORMALMAP_TEXTURE)
sampler NORMALMAP_SAMPLER = sampler_state
{
	ASSIGN_TEXTURE(NORMALMAP_TEXTURE)
	AddressU = WRAP;
	AddressV = WRAP;
	DECLARE_MIPFILTER(LINEAR)
	DECLARE_MINFILTER(LINEAR)
	DECLARE_MAGFILTER(LINEAR)
};

DECLARE_TEXTURE(HEIGHTMAP_TEXTURE)
sampler HEIGHTMAP_SAMPLER = sampler_state
{
	ASSIGN_TEXTURE(HEIGHTMAP_TEXTURE)
};

struct VS_INPUT
{
	float4 position : POSITION;
	float4 color    : COLOR;
	float4 tex		: TEXCOORD;
	float4 size		: TEXCOORD1;
	//int4   light_index	: BLENDINDICES;
	int4   light_index	: TEXCOORD2;
};

struct VtoP_NormalMapped
{
	float4 position			: POSITION;
	float4 color			: COLOR0;
	float3 lightColor		: COLOR1;
	float4 tex				: TEXCOORD0;
	float4 tex1				: TEXCOORD1;
	// vector from the vertex to the light, in tangent space
	float3 to_light_tan		: TEXCOORD2;
	// Half-angle vector, needed for per-pixel specular, in tangent space
	//float3 half_angle_tan	: TEXCOORD3;
	float4 position2			: TEXCOORD3;	
};

struct VtoP
{
	float4 position  : POSITION;
	float4 color     : COLOR0;
	float4 tex       : TEXCOORD0;
	float4 tex1      : TEXCOORD1;
};

struct PS_OUTPUT
{
	float4 color : COLOR0;
};

struct VtoP_Depth
{
	float4 position : POSITION;
	float dist		: COLOR0;
};

//-----------------------------------------------------------------------------
// PARTICLES
//

float3x3 BuildRotate(float angle, float3 rotAxis)
{
	float3x3 m;
	// float fSin = sin(angle);
	// float fCos = cos(angle);
	float2 sc;
	sincos(angle,sc.x,sc.y);
	float3 axis = normalize(rotAxis);

	float3 cosAxis = (1.0f - sc.y) * axis;
	float3 sinAxis = sc.x * axis;
	m[0] = cosAxis.x * axis; 
	m[1] = cosAxis.y * axis; 
	m[2] = cosAxis.z * axis; 
	m[0][0] += sc.y;
	m[0][1] += sinAxis.z;
	m[0][2] -= sinAxis.y;
	m[1][0] -= sinAxis.z;
	m[1][1] += sc.y;
	m[1][2] += sinAxis.x;
	m[2][0] += sinAxis.y;
	m[2][1] -= sinAxis.x;
	m[2][2] += sc.y;
	
	return m;
}

VtoP_NormalMapped vertex_shader_particles(const VS_INPUT IN)
{
	VtoP_NormalMapped OUT;
	// Offset the vertex by the particle size
	float3 right	= cmWorldView._m00_m10_m20;
	float3 up		= cmWorldView._m01_m11_m21;
	float3 facing	= cmWorldView._m02_m12_m22;

	// Rotate the up and right around the facing
	float angle = IN.size.z;
	if( angle > 0 )
	{
		float3x3 rotation = BuildRotate(angle, facing);
		right = mul(right, rotation);
		up	  = mul(up, rotation);
	}

	// Add offset from particle midpoint to the outside vertices
	float4 pv = IN.position;
	float3 offset = right * IN.size.x + up * IN.size.y;
	pv.xyz += offset;

	// Cap the screen size of any particle
	float4 worldCornerPos = pv;
	pv = world_position(pv);

	float3 pvn = pv.xyz/pv.w;
	float4 pc = world_position(IN.position);
	float3 pcn = pc.xyz/pc.w;
	float size = distance(pvn.xy,pcn.xy);
	float new_size = min(size, MaxParticleSize);
	float scale = new_size/size;
	pv = lerp(pc,pv,scale);

	// Each particle is affected by one light in the light array
	// Read which one it is:
	int lightIndex = IN.light_index.x;
	//float3 lightPos = cvLightPosition.xyz;
	float3 lightPos = cavLightPositions[lightIndex].xyz; // PC edit - it uses arrays

	float3 worldPos = mul(IN.position, cmWorldMat);
	float3 toLightSource = normalize(lightPos - worldPos);

	// Create the matrix which transforms from world space to tangent space
	float3 tangent = right;
	float3 binormal = up;
	float3 normal = -facing;
	float3x3 matTSpace = transpose(float3x3( tangent, binormal, normal  ));

	OUT.to_light_tan = mul(toLightSource, matTSpace);

	float3 toEyeWorld = normalize(cvLocalEyePos - worldPos);
	float3 toEyeTan = mul(toEyeWorld, matTSpace);

	// Calculate the half-angle vector for per-pixel specular (maybe this is overkill for particles)
	//OUT.half_angle_tan = (toEyeTan + OUT.to_light_tan) * 0.5;

	float3 lightColour = cavLightColours[lightIndex].xyz; // PC edit - it uses arrays
	//OUT.lightColor = 1;//lightColour;
	OUT.lightColor = lightColour;

	OUT.position = OUT.position2 = pv;
	OUT.color = saturate(IN.color * 2);
	//OUT.color.xyz *= cvAmbientColour.xyz;

	OUT.tex = IN.tex + cvTextureOffset;

	// Convert from screen space (-1 to 1) to texture coordinate space (0.0 to 1.0)
	float distance = pv.z / pv.w;
	OUT.tex1.x = (0.5 * pv.x / pv.w) + 0.5;
	OUT.tex1.y = (-0.5 * pv.y / pv.w) + 0.5;
	//OUT.tex1.y *= cfSplitScreenUVScale[1];	// Split screen adjustment // PC edit - no splitscreen yet
	//OUT.tex1.y += cfSplitScreenUVScale[0];	// Split screen adjustment

	// Distance to the pixel in the depth buffer
	OUT.tex1.z = distance;

	// We cannot use FuzzWidth directly because we are performing these operations in the depth buffer.
	// FuzzWidth is the amount of play that the sprites have with opaque objects. If a sprite is within FuzzWidth of an Opaque object
	// the sprite will get blurred, fading it in nicely with the opaque object and smoothing the harsh edges out

	// Since Ztesting is off, it also controls whether or not we see the sprite if an opaque object is behind it

	// We need to scale FuzzWidth down if the sprite is near the back of the depth buffer. For instance, FuzzWidth could correspond to 1 cm
	// at the start of the depth buffer, but it could be 100 meters at the end of it

	// Calculate the distance from the particle to the camera in world coordinates
	OUT.tex1.w = length(cvLocalEyePos - IN.position) ;


	return OUT;
}

PS_OUTPUT pixel_shader_particles(const VtoP_NormalMapped IN)
{
	PS_OUTPUT OUT;
	float  shadow = 1;//DoShadow( IN.shadowTex, 1 ) * 0.5 + 0.5;

	float4 baseColour = tex2D(DIFFUSE_SAMPLER, IN.tex) * IN.color;

	float depth = tex2D(HEIGHTMAP_SAMPLER, IN.tex1.xy).x;


	float zFar = 10000;
	float zNear = 0.5;
	float Q = zFar / (zFar - zNear);
	float zDist = (-Q * zNear / (depth - Q));

	float depthBufferDistToParticle = IN.position2.z / IN.position2.w;
	float distanceToParticle = (-Q * zNear / (depthBufferDistToParticle - Q));

	float distanceBetweenParticleAndGround = abs(zDist - distanceToParticle);
	float fuzzz = saturate(distanceBetweenParticleAndGround  * 1);

	//fuzzz = 1;

	// calculate the normal map
	float3 normal = tex2D(NORMALMAP_SAMPLER, IN.tex) * 2 - 1;

	normal = normal * magnitude_debug ;

	// Apply diffuse lighting
	float3 toLight = normalize(IN.to_light_tan);
	float nDotL = saturate(dot(normal, toLight));

	float3 diffuseColour = nDotL * IN.lightColor;
	//diffuseColour.xyz = 1;

	// specular calculations
	//float3 half_angle = normalize(IN.half_angle_tan);
	//float nDotH = saturate(dot(normal, half_angle));

	//float3 MaterialSpecular = float3(0.4, 0.4, 0.4);

	//float3 specular = MaterialSpecular * pow(nDotH, MaterialShininess);

	OUT.color.rgb = fuzzz * shadow * baseColour * (ambient_colour + diffuseColour);// + specular);
	OUT.color.a = baseColour.a * shadow * fuzzz;


	//OUT.color.rgb = CompressColourSpace(OUT.color.rgb); // PC edit - we don't really need this here

	return OUT;
}

technique fuzzz <int shader = 1;>
{
	pass p0
	{
		VertexShader = compile vs_1_1 vertex_shader_particles();
		PixelShader  = compile ps_2_0 pixel_shader_particles();
	}
}

technique no_fuzzz <int shader = 1; >
{
	pass p0
	{
		VertexShader = compile vs_1_1 vertex_shader_particles();
		PixelShader = compile ps_2_0 pixel_shader_particles();
	}
}


///////////////////////////////////////////////////////////////////////////////////////
//
// RAINDROPS - CUSTOM SHADERS FOR RAINDROPS - this is needed because raindrops are basically invisible otherwise...
//
///////////////////////////////////////////////////////////////////////////////////////

PS_OUTPUT pixel_shader_raindrop(const VtoP_NormalMapped IN)
{
	PS_OUTPUT OUT;
	float  shadow = 1;//DoShadow( IN.shadowTex, 1 ) * 0.5 + 0.5;

	float4 baseColour = tex2D(DIFFUSE_SAMPLER, IN.tex) * IN.color * 2;

	float depth = tex2D(HEIGHTMAP_SAMPLER, IN.tex1.xy).x;


	float zFar = 10000;
	float zNear = 0.5;
	float Q = zFar / (zFar - zNear);
	float zDist = (-Q * zNear / (depth - Q));

	float depthBufferDistToParticle = IN.position2.z / IN.position2.w;
	float distanceToParticle = (-Q * zNear / (depthBufferDistToParticle - Q));

	float distanceBetweenParticleAndGround = abs(zDist - distanceToParticle);
	float fuzzz = saturate(distanceBetweenParticleAndGround  * 1);

	//fuzzz = 1;

	// calculate the normal map
	float3 normal = tex2D(NORMALMAP_SAMPLER, IN.tex) * 2 - 1;

	normal = normal * magnitude_debug ;

	// Apply diffuse lighting
	float3 toLight = normalize(IN.to_light_tan);
	float nDotL = saturate(dot(normal, toLight));

	float3 diffuseColour = nDotL * IN.lightColor;
	//diffuseColour.xyz = 1;

	// specular calculations
	//float3 half_angle = normalize(IN.half_angle_tan);
	//float nDotH = saturate(dot(normal, half_angle));

	//float3 MaterialSpecular = float3(0.4, 0.4, 0.4);

	//float3 specular = MaterialSpecular * pow(nDotH, MaterialShininess);

	OUT.color.rgb = fuzzz * shadow * baseColour * (ambient_colour + diffuseColour);// + specular);
	OUT.color.a = baseColour.a * shadow * fuzzz;

	return OUT;
}

technique raindrop <int shader = 1;>
{
	pass p0
	{
		FogEnable = FALSE; // NECESSARY - it's affected by sky fog otherwise!

		VertexShader = compile vs_1_1 vertex_shader_particles();
		PixelShader  = compile ps_2_0 pixel_shader_raindrop();
	}
}

///////////////////////////////////////////////////////////////////////////////////////
//
// FLARES
//
///////////////////////////////////////////////////////////////////////////////////////


struct VS_INPUT_FLARES
{
	float4 position : POSITION;
	float4 color    : COLOR;
	float4 tex		: TEXCOORD;
	float4 size		: TEXCOORD1;
};

struct VtoP_FLARES
{
	float4 position  : POSITION;
	float4 color     : COLOR0;
	float4 tex       : TEXCOORD0;
	float4 tex1      : TEXCOORD1;
};

VtoP_FLARES vertex_shader_flares(const VS_INPUT_FLARES IN)
{
	VtoP_FLARES OUT;
	// Offset the vertex by the particle size		
	float3 right	= cmWorldView._m00_m10_m20;
	float3 up		= cmWorldView._m01_m11_m21;
	float3 facing	= cmWorldView._m02_m12_m22;
	float  isTrailFlare = IN.size.w;

	float  angle    = IN.size.z;
	// Rotate the up and right around the facing
	if( angle > 0 )
	{
		float3x3 rotation = BuildRotate(angle, facing);
		right = mul(right, rotation);
		up	  = mul(up, rotation);
	}
	
	float4 pv = IN.position;
	pv.xyz += right * IN.size.x + up * IN.size.y;

	// Cap the screen size of any particle
	pv = world_position(pv);

	OUT.position = pv;
	OUT.color = IN.color;
	OUT.tex = IN.tex;
	OUT.tex.w = cfMipMapBias;		// bias the mipmapping
//	OUT.tex1 = IN.size;


	// Convert from screen space (-1 to 1) to texture coordinate space (0.0 to 1.0)
	float distance = pv.z / pv.w;
	OUT.tex1.x = (0.5 * pv.x / pv.w) + 0.5;
	OUT.tex1.y = (-0.5 * pv.y / pv.w) + 0.5;
	OUT.tex1.z = distance;		// Distance to the pixel in the depth buffer
	//OUT.tex1.y *= cfSplitScreenUVScale[1];	// Split screen adjustment
	//OUT.tex1.y += cfSplitScreenUVScale[0];	// Split screen adjustment

	// We cannot use FuzzWidth directly because we are performing these operations in the depth buffer.
	// FuzzWidth is the amount of play that the sprites have with opaque objects. If a sprite is within FuzzWidth of an Opaque object
	// the sprite will get blurred, fading it in nicely with the opaque object and smoothing the harsh edges out
	
	// Since Ztesting is off, it also controls whether or not we see the sprite if an opaque object is behind it
	
	// We need to scale FuzzWidth down if the sprite is near the back of the depth buffer. For instance, FuzzWidth could correspond to 1 cm
	// at the start of the depth buffer, but it could be 100 meters at the end of it
	OUT.tex1.w = saturate(FuzzWidth + distance * (-FuzzWidth));  

		
	return OUT;
}



float4 pixel_shader_flares(const VtoP_FLARES IN) : COLOR
{
	float4 diffuse = tex2Dbias(DIFFUSE_SAMPLER, IN.tex);

	float scaled_fuzz_width = IN.tex1.w;
	float depth = tex2D(HEIGHTMAP_SAMPLER,IN.tex1.xy).x;
	float fuzzz = saturate((scaled_fuzz_width*0.4 - (IN.tex1.z - depth)) / (scaled_fuzz_width));
	
	
	float4 result;	
	result = diffuse;
	result *= IN.color;//*cvBaseAlphaRef.y;
	// Apply a tone mapping to fake a HDR
	result.xyz = result.xyz / (1.5-result.xyz);
	//result.xyz = pow(result.xyz, 1.5)*1.5;
	//result.xyz	= result.x > 0.95 ? 1.0f : 0.0f;
	// cvBaseAlphaRef.x is set to 0 in players views so the fuzzz used and 1 to disable the fuzz
	result.w *= saturate(cvBaseAlphaRef.x + fuzzz);
	
	//result.xyz = fuzzz;//(scaled_fuzz_width - (IN.tex1.z - depth)) / FuzzWidth;
	//result.w = 1;
	//result.xyz = CompressColourSpace(result.xyz);
	
	return result;
}

technique flares <int shader = 1; >
{
	pass p0
	{
		VertexShader = compile vs_1_1 vertex_shader_flares();
		PixelShader  = compile ps_2_0 pixel_shader_flares();
	}
}

///////////////////////////////////////////////////////////////////////////////////////
//
// STREAK FLARES
//
///////////////////////////////////////////////////////////////////////////////////////

struct VtoP_SFLARES
{
	float4 position  : POSITION;
	float4 color     : COLOR0;
	float4 tex       : TEXCOORD0;
};

VtoP_SFLARES vertex_shader_streak_flares(const VS_INPUT_FLARES IN)
{
	VtoP_SFLARES OUT;
	// Offset the vertex by the particle size
	float3 right	= cmWorldView._m00_m10_m20;
	float3 up		= cmWorldView._m01_m11_m21;
	float3 facing	= cmWorldView._m02_m12_m22;
	float  doStreakFlare = IN.size.w;
	float4 pv		= IN.position;
	float4 vertexColour = IN.color;
	float4 tex		= IN.tex;

	if( doStreakFlare > 0 )
	{
		//float cameraSpeed = cvBaseAlphaRef.y * 75.0;
		float cameraSpeed = cvBaseAlphaRef.y;
		float nosAmount   = cvBaseAlphaRef.w;

		// Add some speed for NOS
		//
		cameraSpeed += nosAmount*20;

		//
		// Flare is stretch to create a flare trail for Sense of Speed
		//
		float4 currFramePos	= mul(IN.position, cmWorldViewProj);

		// Redice length if camera veleocity is off centre in the x direction
		cameraSpeed = lerp(cameraSpeed, 0, saturate(abs(cvBaseAlphaRef.x)/0.05));
		//cameraSpeed = lerp(cameraSpeed, 0, saturate(abs(barx)/0.05));

		float4 prevFramePos = currFramePos;
		prevFramePos.zw += 3 + saturate(cameraSpeed / 140) * 45;		// Stretch flare back
		currFramePos += normalize(currFramePos - prevFramePos) * 10;	// Stretch flare forward



		// Build the poly
		float3 prevFrameDir = prevFramePos.xyz/prevFramePos.w - currFramePos.xyz/currFramePos.w;
		float offsetWidth = min(abs(IN.size.x), abs(IN.size.y));
		offsetWidth *= 0.2;
		float4 currFrameOffset  = mul(IN.position + float4(offsetWidth, offsetWidth, offsetWidth, 0), cmWorldViewProj);
		float  currFrameSize    = distance(currFrameOffset.xy, currFramePos.xy);
		float3 prevFrameDirTanget = normalize(prevFrameDir);
		// Rotate by 90 degrees to get tangent
		prevFrameDirTanget.xy	= prevFrameDirTanget.yx;
		prevFrameDirTanget.x	= -prevFrameDirTanget.x;
		prevFrameDirTanget		*= currFrameSize;

		// Push the tex coord futher along the streak for longer streaks
		float texUlength = saturate(length(prevFrameDir.xyz)/0.1); // 0.3
		tex.x = IN.size.x > 0 ? 1/256 : texUlength;
		tex.y = IN.size.y > 0 ? cvBaseAlphaRef.z : cvBaseAlphaRef.z + 15.0f / 128.0f;	// The v texcoord is calc in on the CPU
		tex.z = IN.size.x > 0 ? 0 : 1;

		// Cap the screen size of any particle
		pv = world_position(pv); // BUG - IF THIS ISNT HERE ITS NOT IN THE CAMERA

		pv = IN.size.x > 0 ? currFramePos : prevFramePos;
		// Adjust brightness for lower/higher speeds
		vertexColour *= saturate(cameraSpeed  / 95);

		// Add the offset to create width for the streak along the tangent
		//
		pv.xy += sign(IN.size.y) * prevFrameDirTanget;
		//pv.z = 1;
	}
	else
	{
		// Push offscreen to clip
		pv = 1000;
	}

	OUT.position = pv;
	OUT.color = vertexColour; // BUG - ITS TRANSPARENT ON PC -- cameraSpeed is INCORRECT
	OUT.tex = tex;
	OUT.tex.w = -5;					// bias the mipmapping
	//OUT.color = IN.color; // uncomment this to make them render always

	return OUT;
}


float4 pixel_shader_streak_flares(const VtoP_SFLARES IN) : COLOR
{
	float4 result = tex2Dbias(DIFFUSE_SAMPLER, IN.tex);;	
	result *= IN.color;
	
	return result;
}

technique streak_flares <int shader = 1;>
{
	pass p0
	{
		VertexShader = compile vs_1_1 vertex_shader_streak_flares();
		PixelShader  = compile ps_2_0 pixel_shader_streak_flares();
	}
}


///////////////////////////////////////////////////////////////////////////////////////
//
// Onscreen rain particle effect
//
struct VtoP_RAIN
{
	float4 position  : POSITION;
	float4 tex       : TEXCOORD0;
};

VtoP_RAIN vertex_shader_passthru(const VS_INPUT IN)
{
	VtoP_RAIN OUT;
	OUT.position = screen_position(IN.position);
	OUT.position.w = 1.0f;
	OUT.tex = IN.tex;

	return OUT;
}

float4 pixel_shader_onscreen_distort(const VtoP_RAIN IN) : COLOR0
{
	float4 distortion = tex2D(DIFFUSE_SAMPLER, IN.tex);
	float2 offset = distortion.gb * cvLocalCenter.ba + cvLocalCenter.rg;
	float4 background = tex2D(MISCMAP1_SAMPLER, offset);
	
	// The opacity map has four different raindrop texture tiled horizontally.  The
	// offset into this texure is stored in cvBaseAlphaRef.y
	//
	offset = IN.tex;
	offset.x = cvBaseAlphaRef.y + IN.tex.x*0.25;
	float4 opacity = tex2D(OPACITY_SAMPLER, offset);
	
	float4 result;
	result = background * opacity.y;
	result.w = opacity.r * cvBaseAlphaRef.x;

	//result = opacity;
	
	return result;
}

technique onscreen_distort <int shader = 1;>
{
	pass p0
	{
		VertexShader = compile vs_1_1 vertex_shader_passthru();
		PixelShader  = compile ps_2_0 pixel_shader_onscreen_distort();
	}
}

//#include "ZPrePass_fx.h" // PC edit - no need for ZPrePass - PC renderer doesn't use it


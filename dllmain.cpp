// NFS Carbon - streak flare restore code

#include "stdafx.h"
#include "stdio.h"
#include <windows.h>
#include <stdlib.h>
#include "includes\injector\injector.hpp"

typedef struct D3DXVECTOR4 {
	FLOAT x;
	FLOAT y;
	FLOAT z;
	FLOAT w;
} D3DXVECTOR4, *LPD3DXVECTOR4;

//int ParticlesShaderObjAddr = 0x00B42FF0;
int ParticlesShaderObj = 0;
int VisualTreatmentPlatAddr = 0x00AB0B80;

void __declspec(naked) FXLEffect_SetVectorFA(int ShaderID, D3DXVECTOR4* pVector)
{
	_asm
	{
		mov     edx, [esp + 8]
		mov     eax, [ecx + 0x44]
		push    esi
		mov     esi, [eax]
		push    edx
		mov     edx, [esp + 0xC]
		lea     edx, [edx + edx * 4]
		mov     ecx, [ecx + edx * 8 + 0x70]
		push    ecx
		push    eax
		call    dword ptr[esi + 0x88]
		pop     esi
		retn    8
	}
}

// set the object address for rain shader here...
#define SHADER_OBJECT_ADDRESS 0x00B42FF0
int sub_73EAE0 = 0x73EAE0;
int sub_710CC0 = 0x710CC0;
int eEffect_SetCurrentPass = 0x00723600;
char* techName = "raindrop"; // custom effect technique added to the shader!
void __declspec(naked) SetRainShader()
{
	_asm
	{
		mov     eax, [esp + 4]
		push    esi
		mov     byte ptr[ecx], 1
		mov     ecx, [eax + 8]
		push    edi
		push    ecx
		push 0
		push techName
		push 0
		mov     ecx, ds: [SHADER_OBJECT_ADDRESS]
		call eEffect_SetCurrentPass
		call    sub_73EAE0
		mov     ecx, ds:[SHADER_OBJECT_ADDRESS]
		mov     edx, [ecx]
		add     esp, 4
		push    0
		push    eax
		mov     eax, [esp + 0x1C]
		push    eax
		call    dword ptr[edx + 8]
		mov     esi, [esp + 0x10]
		mov     ecx, ds: [SHADER_OBJECT_ADDRESS]
		mov     edi, [esi]
		mov     eax, [ecx + 0x44]
		mov     edi, [edi + 0x10]
		mov     ecx, [ecx + 0x660]
		mov     edx, [eax]
		push    edi
		push    ecx
		push    eax
		call    dword ptr[edx + 0x0D0]
		lea     edx, [esp + 0xC]
		push    edx
		mov     ecx, 0xAAF558
		mov     ds : [0xAB0AB4] , esi
		call    sub_710CC0
		pop     edi
		mov     al, 1
		pop     esi
		retn 0x10
	}
}


void __cdecl FXLEffect_SetVectorFA_Hook(int ShaderID, D3DXVECTOR4* pVector)
{
	// Vector in question is cvBaseAlphaRef
	pVector->y = *(float*)((*(int*)VisualTreatmentPlatAddr) + 0xB4); // cameraSpeed
	pVector->w = *(float*)((*(int*)VisualTreatmentPlatAddr) + 0x34); // nosAmount
	pVector->x = *(float*)((*(int*)VisualTreatmentPlatAddr) + 0xC0); // camera x direction - tested by Aero_ - thanks for allowing me to pick your brains!
	//pVector->x = 0;
	// z we keep intact... that's the var that switches between animation frames

	ParticlesShaderObj = *(int*)0x00B42FF0;
	_asm mov ecx, ParticlesShaderObj
	return FXLEffect_SetVectorFA(ShaderID, pVector);
}

int Init()
{
	injector::MakeCALL(0x00749FF0, FXLEffect_SetVectorFA_Hook, true);
	//injector::MakeCALL(0x00749F1C, FXLEffect_SetVectorFA_Hook, true); // causes flicker in motion blur
	injector::MakeCALL(0x007C5882, SetRainShader, true);

	return 0;
}

BOOL APIENTRY DllMain(HMODULE /*hModule*/, DWORD reason, LPVOID /*lpReserved*/)
{
	if (reason == DLL_PROCESS_ATTACH)
	{
		Init();
	}
	return TRUE;
}


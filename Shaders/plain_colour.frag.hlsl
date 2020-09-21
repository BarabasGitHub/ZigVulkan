#include "rectangle.hlsl"

float4 main(float4 pos : SV_POSITION) : SV_TARGET
{
    return g_rectangle_colour;
}

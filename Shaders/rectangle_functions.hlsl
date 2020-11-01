#include "complex.hlsl"

float4 CreateRectangleVertex(uint vertex_index, float3 center, float2 extent, float2 rotation)
{
    float4 position;
    // (-1, -1), (1, -1), (-1, 1), (1, 1)
    position.x = int(vertex_index & 1) * 2 - 1;
    position.y = int(vertex_index & 2) - 1;
    position.xy *= extent;
    position.xy = ComplexMultiply(position.xy, rotation);
    position.xy += center.xy;
    position.z = center.z;
    position.w = 1;
    return position;
}

float2 CreateRectangleUV(uint vertex_index, float2 topleft, float2 bottomright)
{
    float2 uv;
    // (0, 0), (1, 0), (0, 1), (1, 1)
    uv.x = (vertex_index & 1) ? bottomright.x : topleft.x;
    uv.y = (vertex_index & 2) ? bottomright.y : topleft.y;
    return uv;
}

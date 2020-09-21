#include "rectangle_functions.hlsl"

float4 main( uint vertex_index : SV_VertexID ) : SV_POSITION
{
    return CreateRectangleVertex(vertex_index, 0, 0.5, float2(1,0));
}

#include "rectangle_functions.hlsl"
#include "types.hlsl"

PositionTexture main( uint vertex_index : SV_VertexID )
{
    PositionTexture output;
    output.position = CreateRectangleVertex(vertex_index, 0, 0.5, float2(1,0));
    output.uv = CreateRectangleUV(vertex_index);
    return output;
}

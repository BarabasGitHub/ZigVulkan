#include "rectangle.hlsl"
#include "rectangle_functions.hlsl"
#include "types.hlsl"

PositionTexture main( uint vertex_index : SV_VertexID )
{
    PositionTexture output;
    output.position = CreateRectangleVertex(vertex_index, g_rectangle_center, g_rectangle_extent, g_rectangle_rotation);
    output.uv = CreateRectangleUV(vertex_index, g_rectangle_uv_topleft, g_rectangle_uv_bottomright);
    return output;

}

#include "rectangle.hlsl"
#include "rectangle_functions.hlsl"

float4 main( uint vertex_index : SV_VertexID ) : SV_POSITION
{
    return CreateRectangleVertex(vertex_index, g_rectangle_center, g_rectangle_extent, g_rectangle_rotation);
}

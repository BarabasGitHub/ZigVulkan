
float4 CreateRectangleVertex(uint vertex_index)
{
    float4 position;
    // (-1, -1), (1, -1), (-1, 1), (1, 1)
    position.x = int(vertex_index & 1) * 2 - 1;
    position.y = int(vertex_index & 2) - 1;
    position.z = 0;
    position.xy *= 0.5;
    position.w = 1;
    return position;
}

float4 main( uint vertex_index : SV_VertexID ) : SV_POSITION
{
    return CreateRectangleVertex(vertex_index);
}

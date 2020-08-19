
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

float2 CreateRectangleUV(uint vertex_index)
{
    float2 uv;
    // // (0, 0), (1, 0), (0, 1), (1, 1), (0, 1), (1, 0)
    // uv.x = (vertex_index & 1);
    // uv.y = (vertex_index & 4) ? (1 - uv.x) : ((vertex_index & 2) / 2);
    // (0, 1), (1, 1), (0, 0), (1, 0), (0, 0), (1, 1)
    uv.x = (vertex_index & 1) ? 1 : 0;
    uv.y = (((vertex_index + 1) % 6) < 3) ? 1 : 0;
    return uv;
}

struct PositionTexture
{
    float4 position : SV_POSITION; // screen position
    float2 uv : TEXTURE;
};

PositionTexture main( uint vertex_index : SV_VertexID )
{
    PositionTexture output;
    output.position = CreateRectangleVertex(vertex_index);
    output.uv = CreateRectangleUV(vertex_index);
    return output;
}

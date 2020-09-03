cbuffer Rectangle : register(b1)
{
    float2 g_rectangle_extent : packoffset(c0.x);
    float2 g_rectangle_rotation : packoffset(c0.z); // complex
    float3 g_rectangle_center : packoffset(c1); // last is depth
    float4 g_rectangle_colour : packoffset(c2);
};

float2 ComplexMultiply(float2 a, float2 b)
{
    float real = a.x * b.x - a.y * b.y;
    float imaginary = a.x * b.y + a.y * b.x;
    // return {a.r * b.r - a.i * b.i, a.r * b.i + a.i * b.r};
    return float2(real, imaginary);
}

float4 CreateRectangleVertex(uint vertex_index)
{
    float4 position;
    // (-1, -1), (1, -1), (-1, 1), (1, 1)
    position.x = int(vertex_index & 1) * 2 - 1;
    position.y = int(vertex_index & 2) - 1;
    position.xy *= g_rectangle_extent;
    position.xy = ComplexMultiply(position.xy, g_rectangle_rotation);
    position.xy += g_rectangle_center.xy;
    position.z = g_rectangle_center.z;
    position.w = 1;
    return position;
}

float4 main( uint vertex_index : SV_VertexID ) : SV_POSITION
{
    return CreateRectangleVertex(vertex_index);
}

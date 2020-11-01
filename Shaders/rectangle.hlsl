cbuffer Rectangle : register(b1)
{
    float2 g_rectangle_extent : packoffset(c0.x);
    float2 g_rectangle_rotation : packoffset(c0.z); // complex
    float3 g_rectangle_center : packoffset(c1); // last is depth
    float2 g_rectangle_uv_topleft : packoffset(c2.x);
    float2 g_rectangle_uv_bottomright : packoffset(c2.z);
    float4 g_rectangle_colour : packoffset(c3);
};

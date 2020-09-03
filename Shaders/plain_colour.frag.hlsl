cbuffer Rectangle : register(b1)
{
    float2 g_rectangle_extent : packoffset(c0.x);
    float2 g_rectangle_rotation : packoffset(c0.z); // complex
    float3 g_rectangle_center : packoffset(c1); // last is depth
    float4 g_rectangle_colour : packoffset(c2);
};

float4 main(float4 pos : SV_POSITION) : SV_TARGET
{
    return g_rectangle_colour;
}

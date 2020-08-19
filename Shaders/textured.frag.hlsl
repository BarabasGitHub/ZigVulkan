SamplerState TextureSampler : register(s2);
Texture2D TextureMap : register(t3);

struct PositionTexture
{
    float4 position : SV_POSITION; // screen position
    float2 uv : TEXTURE;
};

float4 main( PositionTexture input ) : SV_TARGET
{
    return TextureMap.Sample( TextureSampler, input.uv );
}

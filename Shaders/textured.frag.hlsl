#include "types.hlsl"

SamplerState TextureSampler : register(s2);
Texture2D TextureMap : register(t3);

float4 main( PositionTexture input ) : SV_TARGET
{
    return TextureMap.Sample( TextureSampler, input.uv );
}

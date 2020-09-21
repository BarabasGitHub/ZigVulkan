float2 ComplexMultiply(float2 a, float2 b)
{
    float real = a.x * b.x - a.y * b.y;
    float imaginary = a.x * b.y + a.y * b.x;
    // return {a.r * b.r - a.i * b.i, a.r * b.i + a.i * b.r};
    return float2(real, imaginary);
}

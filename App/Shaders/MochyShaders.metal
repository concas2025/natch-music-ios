#include <metal_stdlib>
using namespace metal;

[[stitchable]] half4 mochyAmbientBlob(
    float2 position,
    half4 color,
    float2 size,
    float time,
    half4 c0,
    half4 c1,
    half4 c2,
    half4 c3
) {
    float2 uv = position / max(size, float2(1.0));
    float2 p0 = float2(0.5 + 0.30 * sin(time * 0.35), 0.32 + 0.24 * cos(time * 0.28));
    float2 p1 = float2(0.5 + 0.32 * cos(time * 0.24), 0.68 + 0.24 * sin(time * 0.31));
    float2 p2 = float2(0.38 + 0.26 * sin(time * 0.41 + 1.5), 0.50 + 0.28 * cos(time * 0.22));
    float2 p3 = float2(0.62 + 0.25 * cos(time * 0.33 + 2.1), 0.45 + 0.24 * sin(time * 0.38));

    float w0 = exp(-3.2 * length(uv - p0));
    float w1 = exp(-3.2 * length(uv - p1));
    float w2 = exp(-3.5 * length(uv - p2));
    float w3 = exp(-3.7 * length(uv - p3));
    float wSum = max(0.001, w0 + w1 + w2 + w3);

    half4 mixColor = (c0 * half(w0) + c1 * half(w1) + c2 * half(w2) + c3 * half(w3)) / half(wSum);
    return half4(mixColor.rgb * half(0.76), half(1.0));
}

[[stitchable]] half4 mochyFilmGrain(
    float2 position,
    half4 color,
    float strength,
    float time
) {
    float noise = fract(sin(dot(position + fract(time) * 60.0, float2(12.9898, 78.233))) * 43758.5453);
    half delta = half((noise - 0.5) * strength);
    return half4(clamp(color.rgb + delta, half(0.0), half(1.0)), color.a);
}

[[stitchable]] half4 mochySeamFade(
    float2 position,
    half4 color,
    float2 size,
    float fadeStart
) {
    float yNorm = clamp(position.y / max(size.y, 1.0), 0.0, 1.0);
    float fade = 1.0 - smoothstep(fadeStart, 1.0, yNorm);
    return half4(color.rgb * half(fade), color.a * half(fade));
}

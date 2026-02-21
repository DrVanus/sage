//
//  PerlinNoise.metal
//  CSAI1
//
//  Created by DM on 3/25/25.
//
//  GPU-accelerated Perlin noise shader for premium background texture.
//  Creates smooth, organic animated noise used as an overlay effect.
//

#include <metal_stdlib>
using namespace metal;

// MARK: - Complete Permutation Table
// Standard Perlin noise permutation table (Ken Perlin's reference implementation)
constant int perm[512] = {
    151,160,137,91,90,15,131,13,201,95,96,53,194,233,7,225,140,36,103,30,69,142,
    8,99,37,240,21,10,23,190,6,148,247,120,234,75,0,26,197,62,94,252,219,203,117,
    35,11,32,57,177,33,88,237,149,56,87,174,20,125,136,171,168,68,175,74,165,71,
    134,139,48,27,166,77,146,158,231,83,111,229,122,60,211,133,230,220,105,92,41,
    55,46,245,40,244,102,143,54,65,25,63,161,1,216,80,73,209,76,132,187,208,89,
    18,169,200,196,135,130,116,188,159,86,164,100,109,198,173,186,3,64,52,217,226,
    250,124,123,5,202,38,147,118,126,255,82,85,212,207,206,59,227,47,16,58,17,182,
    189,28,42,223,183,170,213,119,248,152,2,44,154,163,70,221,153,101,155,167,43,
    172,9,129,22,39,253,19,98,108,110,79,113,224,232,178,185,112,104,218,246,97,
    228,251,34,242,193,238,210,144,12,191,179,162,241,81,51,145,235,249,14,239,
    107,49,192,214,31,181,199,106,157,184,84,204,176,115,121,50,45,127,4,150,254,
    138,236,205,93,222,114,67,29,24,72,243,141,128,195,78,66,215,61,156,180,
    // Repeat for wrap-around
    151,160,137,91,90,15,131,13,201,95,96,53,194,233,7,225,140,36,103,30,69,142,
    8,99,37,240,21,10,23,190,6,148,247,120,234,75,0,26,197,62,94,252,219,203,117,
    35,11,32,57,177,33,88,237,149,56,87,174,20,125,136,171,168,68,175,74,165,71,
    134,139,48,27,166,77,146,158,231,83,111,229,122,60,211,133,230,220,105,92,41,
    55,46,245,40,244,102,143,54,65,25,63,161,1,216,80,73,209,76,132,187,208,89,
    18,169,200,196,135,130,116,188,159,86,164,100,109,198,173,186,3,64,52,217,226,
    250,124,123,5,202,38,147,118,126,255,82,85,212,207,206,59,227,47,16,58,17,182,
    189,28,42,223,183,170,213,119,248,152,2,44,154,163,70,221,153,101,155,167,43,
    172,9,129,22,39,253,19,98,108,110,79,113,224,232,178,185,112,104,218,246,97,
    228,251,34,242,193,238,210,144,12,191,179,162,241,81,51,145,235,249,14,239,
    107,49,192,214,31,181,199,106,157,184,84,204,176,115,121,50,45,127,4,150,254,
    138,236,205,93,222,114,67,29,24,72,243,141,128,195,78,66,215,61,156,180
};

// MARK: - Noise Functions

// Smooth interpolation curve: 6t^5 - 15t^4 + 10t^3
inline float fade(float t) {
    return t * t * t * (t * (t * 6.0f - 15.0f) + 10.0f);
}

// Gradient function for 2D
inline float grad2(int hash, float x, float y) {
    int h = hash & 7;
    float u = h < 4 ? x : y;
    float v = h < 4 ? y : x;
    return ((h & 1) ? -u : u) + ((h & 2) ? -2.0f * v : 2.0f * v);
}

// 2D Perlin noise implementation
float perlinNoise2D(float2 P) {
    // Integer coordinates
    int xi = int(floor(P.x)) & 255;
    int yi = int(floor(P.y)) & 255;
    
    // Fractional coordinates
    float xf = P.x - floor(P.x);
    float yf = P.y - floor(P.y);
    
    // Fade curves
    float u = fade(xf);
    float v = fade(yf);
    
    // Hash coordinates of the 4 corners
    int aa = perm[perm[xi] + yi];
    int ab = perm[perm[xi] + yi + 1];
    int ba = perm[perm[xi + 1] + yi];
    int bb = perm[perm[xi + 1] + yi + 1];
    
    // Blend the gradients
    float x1 = mix(grad2(aa, xf, yf), grad2(ba, xf - 1.0f, yf), u);
    float x2 = mix(grad2(ab, xf, yf - 1.0f), grad2(bb, xf - 1.0f, yf - 1.0f), u);
    
    return mix(x1, x2, v);
}

// Fractal Brownian Motion - layered noise for richer texture
float fbm(float2 p, int octaves) {
    float value = 0.0f;
    float amplitude = 0.5f;
    float frequency = 1.0f;
    
    for (int i = 0; i < octaves; i++) {
        value += amplitude * perlinNoise2D(p * frequency);
        amplitude *= 0.5f;
        frequency *= 2.0f;
    }
    
    return value;
}

// MARK: - Shader Structures

struct Uniforms {
    float time;
    float2 resolution;
};

struct VertexOut {
    float4 position [[position]];
    float2 uv;
};

// MARK: - Vertex Shader

vertex VertexOut v_main(
    uint vid [[vertex_id]],
    constant Uniforms& u [[buffer(1)]])
{
    VertexOut out;
    
    // Full-screen triangle approach (more efficient than quad)
    float2 positions[3] = {
        float2(-1.0f, -1.0f),
        float2( 3.0f, -1.0f),
        float2(-1.0f,  3.0f)
    };
    
    out.position = float4(positions[vid], 0.0f, 1.0f);
    
    // Calculate UV with aspect ratio correction
    float aspectRatio = u.resolution.x / u.resolution.y;
    float2 uv = positions[vid] * 0.5f + 0.5f;
    uv.x *= aspectRatio;
    out.uv = uv;
    
    return out;
}

// MARK: - Fragment Shader

fragment half4 f_main(
    VertexOut in [[stage_in]],
    constant Uniforms& u [[buffer(0)]])
{
    // Scale coordinates for appropriate noise detail
    float2 coords = in.uv * 2.5f;
    
    // Slow, smooth animation
    float timeScale = u.time * 0.08f;
    coords += float2(timeScale * 0.3f, timeScale * 0.2f);
    
    // Use FBM for richer, more organic noise texture
    // 3 octaves provides good detail without being too busy
    float n = fbm(coords, 3);
    
    // Map noise from [-1, 1] to [0, 1] range
    float shade = 0.5f + 0.4f * n;
    
    // Subtle contrast enhancement
    shade = smoothstep(0.3f, 0.7f, shade);
    
    // Output grayscale with slight transparency variation
    // The opacity varies slightly with the noise for depth
    float alpha = 0.8f + 0.2f * shade;
    
    return half4(half3(shade), half(alpha));
}

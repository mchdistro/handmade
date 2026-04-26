#version 330

#define parallaxIntensity 2.5
#define PI 3.14159265359

uniform mat4 ModelViewMat;
uniform mat4 ProjMat;
uniform vec2 size;
uniform vec2 scrollOffset;
uniform vec2 scrollSize;
uniform float time;
uniform float zoom;

in vec2 texCoord0;
out vec4 fragColor;

// --- Noise Functions ---
uint hash(uint x) {
    x += (x << 10u);
    x ^= (x >> 6u);
    x += (x << 3u);
    x ^= (x >> 11u);
    x += (x << 15u);
    return x;
}
uint hash(uvec2 v) { return hash(v.x ^ hash(v.y)); }

float floatConstruct(uint m) {
    const uint ieeeMantissa = 0x007FFFFFu;
    const uint ieeeOne = 0x3F800000u;
    m &= ieeeMantissa;
    m |= ieeeOne;
    float f = uintBitsToFloat(m);
    return f - 1.0;
}

float random(vec2 v) { return floatConstruct(hash(floatBitsToUint(v))); }
vec2 random2(vec2 v) {
    return vec2(
        floatConstruct(hash(floatBitsToUint(v))),
        floatConstruct(hash(floatBitsToUint(v * 2.0)))
    ) * 2.0 - 1.0;
}

float noise(vec2 st) {
    vec2 i = floor(st);
    vec2 f = fract(st);
    vec2 u = f * f * (3.0 - 2.0 * f);
    return mix(
        mix(dot(random2(i + vec2(0.0, 0.0)), f - vec2(0.0, 0.0)),
            dot(random2(i + vec2(1.0, 0.0)), f - vec2(1.0, 0.0)), u.x),
        mix(dot(random2(i + vec2(0.0, 1.0)), f - vec2(0.0, 1.0)),
            dot(random2(i + vec2(1.0, 1.0)), f - vec2(1.0, 1.0)), u.x),
        u.y
    ) * 0.5 + 0.5;
}

float fbm(vec2 uv, int octaves) {
    float value = 0.0;
    float amp = 0.5;
    for (int i = 0; i < octaves; i++) {
        value += amp * noise(uv);
        uv *= 2.0;
        amp *= 0.5;
    }
    return value;
}

// Fluid warping FBM for the Void
float fbmVoid(vec2 uv, float t) {
    vec2 q = vec2(fbm(uv + t * 0.15, 3), fbm(uv + vec2(5.2, 1.3) - t * 0.1, 3));
    vec2 r = vec2(fbm(uv + 4.0 * q + vec2(1.7, 9.2) + t * 0.2, 3), fbm(uv + 4.0 * q + vec2(8.3, 2.8) - t * 0.15, 3));
    return fbm(uv + 4.0 * r, 4);
}

// --- Lightning Arc ---
float lightningArc(vec2 uv, vec2 a, vec2 b, float t, float scale) {
    vec2 pa = uv - a;
    vec2 ba = b - a;
    float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    
    float n = fbm(vec2(h * 20.0, t * 6.0), 3) - 0.5;
    n += (fbm(vec2(h * 40.0, -t * 10.0), 2) - 0.5) * 0.5;
    n *= smoothstep(0.0, 0.05, h) * smoothstep(1.0, 0.95, h);
    
    vec2 perp = normalize(vec2(-ba.y, ba.x));
    vec2 d = pa - ba * h + perp * n * length(ba) * 0.2; 
    
    float dist = length(d);
    float scaledDist = dist * scale;
    
    float core = exp(-scaledDist * 100.0);
    float glow = 0.4 / (1.0 + scaledDist * 20.0);
    
    return core + glow;
}

// --- Space Particles ---
vec3 endParticles(vec2 fragCoord, float t, vec2 scroll, float scale, vec2 dir, float seedOffset, vec2 vortexCenter) {
    vec3 pCol = vec3(0.0);
    for (float layer = 0.0; layer < 2.0; layer += 1.0) {
        float cellsize = (50.0 + layer * 35.0) * 0.66; // 50% more zoomed out
        float parallaxMult = 20.0 + layer * 15.0;
        
        vec2 coord = fragCoord + vec2(layer * 200.0 + seedOffset) + (scroll * parallaxMult * parallaxIntensity) / scale;
        
        // Swirling inwards to vortex
        vec2 relToVortex = coord - vortexCenter * scale;
        float distToVortex = length(relToVortex);
        float angle = atan(relToVortex.y, relToVortex.x);
        
        // Sucked in
        distToVortex -= t * (150.0 + layer * 50.0) * 0.66; // Scaled to match zoom
        // Spiral
        angle += t * (0.5 - layer * 0.1);
        
        coord = vec2(cos(angle), sin(angle)) * distToVortex + vortexCenter * scale;
        
        vec2 cell = floor(coord / cellsize);
        vec2 luv = fract(coord / cellsize) - 0.5;
        
        float presence = random(cell + vec2(seedOffset, 17.2));
        if (presence > 0.8) {
            vec2 pos = vec2((random(cell + 3.0) - 0.5) * 0.7, (random(cell + 4.0) - 0.5) * 0.7);
            
            float d = length(luv - pos) * cellsize;
            float core = exp(-d * d * 15.0);
            float glow = 0.8 / (1.0 + d * d * 0.8);
            float pulse = 0.5 + 0.5 * sin(t * 8.0 + random(cell + 7.0) * 6.28);
            
            vec3 color = vec3(0.8, 0.2, 1.0); // Magenta
            if (random(cell + 9.0) > 0.6) color = vec3(0.2, 0.8, 1.0); // Cyan
            if (random(cell + 12.0) > 0.8) color = vec3(0.1, 1.0, 0.5); // Ender green
            
            pCol += color * (core + glow) * pulse;
        }
    }
    return pCol;
}

void main() {
    vec2 fragCoord = texCoord0 * size;
    vec2 center = size / 2.0;
    float scale = zoom / 16.0;
    
    vec2 relative = fragCoord - center;
    relative /= scale;
    vec2 zoomed_frag = relative + center;
    vec2 base_uv = zoomed_frag / size;
    
    float aspect = size.x / size.y;
    base_uv.x *= aspect;
    vec2 zoomed_uv = base_uv;
    
    vec2 scrollPos = vec2(0.0);
    if (scrollSize.x > 0.0) scrollPos.x = scrollOffset.x / scrollSize.x;
    if (scrollSize.y > 0.0) scrollPos.y = scrollOffset.y / scrollSize.y;
    
    float slowTime = time * 0.16875; // Slowed down by 25% from 0.225
    float starTime = time * 0.03375; // Slowed down by 25% from 0.045
    vec2 vortexCenter = vec2(aspect * 0.5, 0.5);
    
    // === LAYER 1: The Void (Deep Background) ===
    vec3 voidDark = vec3(0.01, 0.0, 0.02);
    vec3 voidMid = vec3(0.05, 0.01, 0.08);
    float bgNoise = fbm(zoomed_uv * 2.0 + slowTime * 0.075, 3); // Slowed down by 25%
    vec3 bgCol = mix(voidDark, voidMid, bgNoise);
    fragColor = vec4(bgCol, 1.0);
    
    // === LAYER 2: The Swirling Eye of Nothingness ===
    vec2 eye_uv = (zoomed_uv - vortexCenter) * 1.5 + vortexCenter; // 66% size
    vec2 diff = eye_uv - vortexCenter + (scrollPos * 0.01 * parallaxIntensity) / scale;
    float dist = length(diff);
    float angle = atan(diff.y, diff.x);
    
    // Twisting effect
    float twist = angle + slowTime * 0.6 + 0.2 / (dist + 0.05); // Slowed down by 25%
    vec2 twisted_uv = vec2(cos(twist), sin(twist)) * dist + vortexCenter;
    
    float riftFbm = fbmVoid(twisted_uv * 2.5, slowTime * 0.75); // Slowed down by 25%
    float riftFbm2 = fbmVoid(twisted_uv * 4.0 - vec2(slowTime * 0.375), slowTime * 1.125); // Slowed down by 25%
    
    float riftMix = max(riftFbm * 0.8, riftFbm2 * 0.9);
    
    // Intense magenta/purple/black colors
    vec3 riftDark = vec3(0.1, 0.0, 0.15);
    vec3 riftMid = vec3(0.5, 0.05, 0.4);
    vec3 riftBright = vec3(0.9, 0.2, 1.0);
    vec3 riftCore = vec3(0.0, 0.0, 0.0); // Black hole core
    
    vec3 rCol = mix(riftDark, riftMid, smoothstep(0.3, 0.6, riftMix));
    rCol = mix(rCol, riftBright, smoothstep(0.6, 0.85, riftMix));
    
    // Suck into the core
    float coreMask = smoothstep(0.02, 0.15, dist);
    // Outer fade
    float outerMask = smoothstep(0.9, 0.3, dist);
    
    vec3 finalRift = rCol * coreMask * outerMask;
    
    // The Event Horizon (bright ring around the black hole)
    float horizon = smoothstep(0.05, 0.02, abs(dist - 0.12));
    float horizonGlow = 0.05 / (abs(dist - 0.12) + 0.01);
    vec3 horizonColor = vec3(0.8, 0.2, 1.0) * (horizon + horizonGlow * 0.5);
    
    // Dark core
    finalRift += horizonColor * (1.0 - smoothstep(0.0, 0.1, dist - 0.12));
    finalRift *= smoothstep(0.08, 0.12, dist); // Enforce black hole
    
    fragColor.rgb += finalRift * 1.5;
    
    // === LAYER 3: Chaos Energy & Lightning ===
    float bolt = 0.0;
    float flashTime = slowTime * 3.0; // Slowed down by 25%
    float lseed = floor(flashTime);
    float localTime = fract(flashTime);
    
    float flashEnvelope = exp(-localTime * 10.0);
    
    if (random(vec2(lseed, 5.0)) > 0.3) { 
        // Lightning arcing from the void to the edges
        float ang1 = random(vec2(lseed, 6.0)) * 2.0 * PI;
        vec2 start = vortexCenter + vec2(cos(ang1), sin(ang1)) * 0.15; // Near horizon
        
        float ang2 = ang1 + (random(vec2(lseed, 7.0)) - 0.5) * PI * 0.5;
        vec2 end = vortexCenter + vec2(cos(ang2), sin(ang2)) * (0.8 + random(vec2(lseed, 8.0)) * 0.5);
        
        bolt += lightningArc(eye_uv, start, end, slowTime, scale);
        
        if (random(vec2(lseed, 9.0)) > 0.5) {
            vec2 mid = mix(start, end, 0.4 + (random(vec2(lseed, 10.0)) - 0.5) * 0.3);
            float ang3 = ang2 + (random(vec2(lseed, 11.0)) > 0.5 ? 0.5 : -0.5);
            vec2 branchEnd = mid + vec2(cos(ang3), sin(ang3)) * 0.4;
            bolt += lightningArc(eye_uv, mid, branchEnd, slowTime + 0.1, scale);
        }
    }
    
    bolt *= flashEnvelope;
    vec3 lightningColor = mix(vec3(0.9, 0.3, 1.0), vec3(0.3, 0.9, 1.0), random(vec2(lseed, 12.0)));
    fragColor.rgb += lightningColor * bolt * 2.5;
    
    // Background flash
    fragColor.rgb += lightningColor * bolt * 0.1 * outerMask;
    
    // === LAYER 4: Space Dust / Nebula Clouds ===
    vec2 dust_uv = zoomed_uv * 3.0 + (scrollPos * 0.02 * parallaxIntensity) / scale;
    float dust = fbm(dust_uv + vec2(100.0, 50.0) - slowTime * 0.15, 3); // Slowed down by 25%
    dust = smoothstep(0.4, 0.8, dust);
    
    vec3 dustColor = vec3(0.2, 0.05, 0.3); // Deep end purple
    fragColor.rgb += dustColor * dust * 0.8 * outerMask;
    
    // === LAYER 5: Ender Particles (Stars falling into void) ===
    vec3 particles = endParticles(zoomed_frag, starTime, scrollPos, scale, vec2(0.0), 300.0, vec2(0.5, 0.5)); // Using non-aspect center for particles due to screen space
    
    // Only show particles outside the core
    fragColor.rgb += particles * smoothstep(0.05, 0.15, dist);
    
    // --- Post Processing ---
    vec2 uvNorm = texCoord0;
    float distEdge = distance(uvNorm, vec2(0.5));
    float vignette = 1.0 - smoothstep(0.2, 0.9, distEdge);
    vec3 vignetteColor = mix(vec3(0.02, 0.0, 0.05), vec3(1.0), vignette);
    fragColor.rgb *= vignetteColor;
    
    fragColor.rgb = mix(vec3(0.01), fragColor.rgb, 1.1);
    
    fragColor = clamp(fragColor, 0.0, 1.0);
}

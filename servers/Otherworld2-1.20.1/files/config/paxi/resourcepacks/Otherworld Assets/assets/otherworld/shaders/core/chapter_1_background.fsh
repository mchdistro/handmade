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

// --- RUNE GEN ---
float sdLine(vec2 p, vec2 a, vec2 b) {
    vec2 pa = p - a, ba = b - a;
    float h = clamp(dot(pa, ba) / max(dot(ba, ba), 0.0001), 0.0, 1.0);
    return length(pa - ba * h);
}

float getRune(vec2 uv, float seed) {
    float d = 1.0;
    float s = random(vec2(seed, 1.1));
    
    // Construct ancient lich-like jagged symbols
    if (s < 0.5) {
        d = min(d, sdLine(uv, vec2(0.0, -0.175), vec2(0.0, 0.175)));
        int branches = 1 + int(random(vec2(seed, 2.2)) * 3.0);
        for (int i = 0; i < branches; i++) {
            float fi = float(i);
            vec2 bSeed = vec2(seed, fi * 1.56);
            float h = floor(random(bSeed) * 4.0);
            float y = -0.15 + h * 0.1;
            float side = random(bSeed + 0.1) > 0.5 ? 1.0 : -1.0;
            float type = floor(random(bSeed + 0.2) * 3.0);
            
            vec2 start = vec2(0.0, y);
            vec2 end = vec2(0.125 * side, y + (type - 1.0) * 0.1);
            d = min(d, sdLine(uv, start, end));
        }
    } else {
        d = min(d, sdLine(uv, vec2(-0.08, -0.15), vec2(0.08, 0.15)));
        d = min(d, sdLine(uv, vec2(0.08, -0.15), vec2(-0.08, 0.15)));
        if (random(vec2(seed, 3.3)) < 0.5) {
            d = min(d, sdLine(uv, vec2(0.0, -0.2), vec2(0.0, 0.2)));
        } else {
            d = min(d, sdLine(uv, vec2(-0.1, 0.0), vec2(0.1, 0.0)));
        }
    }
    return d;
}

vec3 renderRunes(vec2 zoomed_frag, float t, vec2 scroll, float scale) {
    vec3 runeCol = vec3(0.0);
    for (float i = 0.0; i < 2.0; i += 1.0) {
        float cellsize = 120.0 + i * 60.0;
        float parallaxMult = 10.0 + i * 5.0;
        
        vec2 coord = zoomed_frag + vec2(i * 500.0) + (scroll * parallaxMult * parallaxIntensity) / scale;
        vec2 cell = floor(coord / cellsize);
        vec2 luv = fract(coord / cellsize) - 0.5;
        
        float seed = random(cell + vec2(i * 13.5, 42.0));
        if (seed > 0.91) { // Halved frequency of runes (was 0.82, now 0.91)
            float cycle = t * (0.2 + seed * 0.15) + seed * 62.8;
            float pulse = sin(cycle) * 0.5 + 0.5;
            float fadeInOut = smoothstep(0.0, 0.2, pulse) * smoothstep(1.0, 0.8, pulse);
            
            // Wobble
            vec2 drift = vec2(sin(cycle * 0.4), cos(cycle * 0.6)) * 0.05;
            
            float angle = (random(cell) - 0.5) * 0.5;
            float s = sin(angle), c = cos(angle);
            mat2 rot = mat2(c, -s, s, c);
            
            float runeScale = 0.5;
            vec2 runeUV = ((luv - drift) / runeScale) * rot;
            float d = getRune(runeUV, seed);
            
            float thickness = 0.6 / (cellsize * runeScale);
            float runeVal = smoothstep(thickness, 0.0, d);
            float glow = exp(-d * 40.0) * 0.7;
            
            // Sickly necrotic green / cyan / purple colors
            vec3 color = mix(vec3(0.1, 0.8, 0.5), vec3(0.4, 0.2, 0.8), seed);
            
            runeCol += color * (runeVal + glow) * fadeInOut * 0.25;
        }
    }
    return runeCol;
}

// --- SOULS / WISPS ---
vec3 lostSouls(vec2 fragCoord, float t, vec2 scroll, float scale) {
    vec3 souls = vec3(0.0);
    // Slow down the base time for souls significantly
    float soulTime = t * 0.25; 
    
    for (float layer = 0.0; layer < 3.0; layer += 1.0) {
        float cellsize = 120.0 + layer * 60.0; // Made cells larger so souls appear smaller relative to cell
        float parallaxMult = 15.0 + layer * 10.0;
        
        vec2 coord = fragCoord + vec2(layer * 300.0) + (scroll * parallaxMult * parallaxIntensity) / scale;
        
        // Falling (which visually is moving UP due to flipped screen coordinates)
        coord.y += soulTime * (25.0 + layer * 10.0);
        coord.x += sin(soulTime * 0.5 + layer * 2.0) * 15.0;
        
        vec2 cell = floor(coord / cellsize);
        vec2 luv = fract(coord / cellsize) - 0.5;
        
        float soulPresence = random(cell + vec2(7.3, 11.2));
        if (soulPresence > 0.70) { // Doubled amount of souls (was 0.85, now 0.70)
            vec2 pos = vec2((random(cell + 1.0) - 0.5) * 0.6, (random(cell + 2.0) - 0.5) * 0.6);
            
            // Slower, more subtle wobbling
            pos.x += sin(soulTime * 3.0 + random(cell) * 6.28) * 0.05;
            pos.y += cos(soulTime * 2.0 + random(cell + 3.0) * 6.28) * 0.02;
            
            vec2 diff = luv - pos;
            
            // Fix the aspect ratio to make them more spherical/orb-like rather than oblong lines
            // Removed the x/y distortion and trailing math
            float d = length(diff) * cellsize;
            
            // Much smaller core size (was 0.8, now 3.5)
            float core = exp(-d * d * 3.5);
            // Smaller, tighter glow
            float glow = 0.3 / (1.0 + d * d * 0.2);
            float pulse = 0.7 + 0.3 * sin(soulTime * 3.0 + random(cell + 4.0) * 6.28);
            
            float brightness = (core + glow) * pulse;
            
            // Necrotic colors
            vec3 color = vec3(0.1, 0.9, 0.7); // Cyan-green
            if (random(cell + 5.0) > 0.6) {
                color = vec3(0.3, 0.8, 0.9); // Ghostly blue
            } else if (random(cell + 6.0) > 0.8) {
                color = vec3(0.6, 0.2, 0.8); // Dark purple
            }
            
            souls += color * brightness * 0.6; // Slightly boosted overall brightness to compensate for smaller size
        }
    }
    return souls;
}

// --- ETHEREAL FOG / NECROTIC MIST ---
float necroticFog(vec2 uv, float t, vec2 scroll) {
    // Slowed down fog movement
    uv.x += t * 0.005;
    uv += scroll * 0.02;
    
    // Domain warp for swirliness (slower)
    vec2 warp = vec2(fbm(uv * 2.0 - t * 0.0075, 3), fbm(uv * 2.0 + t * 0.005, 3));
    float c = fbm(uv * 2.5 + warp * 0.5, 4);
    
    return smoothstep(0.2, 0.8, c);
}

// --- SPECTRAL VEINS ---
float spectralVeins(vec2 uv, float t) {
    vec2 p = uv * 3.0;
    // Slowed down vertical pan
    p.y += t * 0.0375; 
    
    float n1 = fbm(p, 3);
    float n2 = fbm(p + vec2(5.2, 1.3), 3);
    
    // Slowed down wave oscillation
    float lines = sin(n1 * 10.0 + t * 0.25) * cos(n2 * 10.0 - t * 0.125);
    
    // Thin glowing edges
    lines = abs(lines);
    lines = 0.015 / (lines + 0.015);
    
    return lines;
}

void main() {
    // --- Coordinates Setup ---
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
    
    // --- Scroll Calculations ---
    vec2 scrollPos = vec2(0.0);
    if (scrollSize.x > 0.0) scrollPos.x = scrollOffset.x / scrollSize.x;
    if (scrollSize.y > 0.0) scrollPos.y = scrollOffset.y / scrollSize.y;
    
    float verticalPos = clamp(texCoord0.y, 0.0, 1.0);
    
    // === LAYER 1: Abyssal Background ===
    // Pitch black at bottom, bruised purple / dark necrotic teal at the top (Flipped)
    vec3 skyTop = vec3(0.05, 0.15, 0.12); // Sickly dark green-teal
    vec3 skyMid = vec3(0.03, 0.05, 0.08);
    vec3 skyBot = vec3(0.01, 0.01, 0.02); 
    
    vec3 skyColor = mix(skyMid, skyTop, smoothstep(0.4, 1.0, verticalPos));
    skyColor = mix(skyBot, skyColor, smoothstep(0.0, 0.4, verticalPos));
    fragColor = vec4(skyColor, 1.0);
    
    // === LAYER 2: Spectral Veins (Background energy) ===
    vec2 vein_uv = zoomed_uv + (scrollPos * 0.02 * parallaxIntensity) / scale;
    float veins = spectralVeins(vein_uv, time);
    vec3 veinColor = vec3(0.1, 0.6, 0.4); // Ghostly green
    fragColor.rgb += veinColor * veins * 0.15 * verticalPos; // Stronger towards the top abyss (Flipped)
    
    // === LAYER 3: Necrotic Graveyard Fog ===
    vec2 fog_uv1 = zoomed_uv * vec2(1.5, 3.0) + (scrollPos * 0.05 * parallaxIntensity) / scale;
    vec2 fog_uv2 = zoomed_uv * vec2(2.5, 4.0) + (scrollPos * 0.1 * parallaxIntensity) / scale;
    
    // Slowed down the time passed into necroticFog for the main render call
    float fog1 = necroticFog(fog_uv1, time * 0.2, scrollPos);
    float fog2 = necroticFog(fog_uv2, -time * 0.125, scrollPos * 1.5);
    
    float fogHeight = 0.4; // How far down the fog reaches from the top
    float fogMask = smoothstep(1.0 - fogHeight, 0.9, verticalPos); // Flipped mask to come from top
    
    vec3 fogColor1 = vec3(0.05, 0.25, 0.20); // Darker teal
    vec3 fogColor2 = vec3(0.15, 0.40, 0.35); // Lighter ghastly green
    
    vec3 finalFog = mix(fogColor1, fogColor2, fog2) * fog1 * fogMask * 1.5;
    fragColor.rgb += finalFog;
    
    // === LAYER 4: Lich Runes ===
    vec3 runes = renderRunes(zoomed_frag, time, scrollPos, scale);
    fragColor.rgb += runes;
    
    // === LAYER 5: Lost Souls / Wisps ===
    vec3 souls = lostSouls(zoomed_frag, time, scrollPos, scale);
    fragColor.rgb += souls;
    
    // --- Post Processing ---
    // Claustrophobic Vignette
    vec2 uvNorm = texCoord0;
    float distEdge = distance(uvNorm, vec2(0.5));
    float vignette = 1.0 - smoothstep(0.3, 0.85, distEdge);
    
    // Tint vignette with very dark purple to match Death Stone vibe
    vec3 vignetteColor = mix(vec3(0.05, 0.0, 0.1), vec3(1.0), vignette);
    fragColor.rgb *= vignetteColor;
    
    // Contrast & Desaturation curve
    // Death theme means high contrast but less vibrant overall colors except for the glowing souls
    float luminance = dot(fragColor.rgb, vec3(0.299, 0.587, 0.114));
    vec3 desaturated = mix(vec3(luminance), fragColor.rgb, 1.2); // slight over-saturation for magic glow
    fragColor.rgb = mix(vec3(0.1) /* dark grey base */, desaturated, 1.15);
    
    fragColor.rgb = clamp(fragColor.rgb, 0.0, 1.0);
}
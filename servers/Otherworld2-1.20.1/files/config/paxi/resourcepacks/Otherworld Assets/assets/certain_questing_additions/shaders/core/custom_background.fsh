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

// Fractal Brownian Motion for clouds/nebula
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

// --- Shooting Star ---
float shootingStar(vec2 uv, float t, float seed) {
    float cycle = 30.0 + random(vec2(seed * 1.5)) * 30.0;
    float phase = random(vec2(seed, seed * 2.0)) * cycle;
    float localTime = mod(t + phase, cycle);
    
    if (localTime > 0.8) return 0.0;
    
    float progress = localTime / 0.8;
    
    float fadeIn = smoothstep(0.0, 0.15, progress);
    float fadeOut = smoothstep(1.0, 0.65, progress);
    float fade = fadeIn * fadeOut;
    
    vec2 startPos = vec2(
        random(vec2(seed * 3.0, seed)),
        random(vec2(seed, seed * 4.0))
    );
    
    float angle = random(vec2(seed * 5.0, seed * 6.0)) * 2.0 * PI;
    vec2 direction = vec2(cos(angle), sin(angle));
    
    float trailLen = 0.02 + random(vec2(seed * 7.0)) * 0.015;
    
    vec2 headPos = startPos + direction * progress * 0.125;
    vec2 tailPos = headPos - direction * trailLen * smoothstep(0.0, 0.25, progress);
    
    vec2 pa = uv - tailPos;
    vec2 ba = headPos - tailPos;
    float h = clamp(dot(pa, ba) / max(dot(ba, ba), 0.0001), 0.0, 1.0);
    float d = length(pa - ba * h);
    
    float brightness = smoothstep(0.001, 0.0, d) * h * fade;
    brightness += smoothstep(0.003, 0.0, d) * h * fade * 0.15;
    
    return brightness;
}

// --- Magical Runes ---
float sdLine(vec2 p, vec2 a, vec2 b) {
    vec2 pa = p - a, ba = b - a;
    float h = clamp(dot(pa, ba) / max(dot(ba, ba), 0.0001), 0.0, 1.0);
    return length(pa - ba * h);
}

float getRune(vec2 uv, float seed) {
    float d = 1.0;
    float s = random(vec2(seed, 1.1));
    
    // Base shape selection - Cirth style
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
            
            if (random(bSeed + 0.3) > 0.7) {
                float y2 = y + (type - 1.0) * 0.2;
                d = min(d, sdLine(uv, end, vec2(0.0, y2)));
            }
        }
    } else if (s < 0.65) {
        d = min(d, sdLine(uv, vec2(-0.06, -0.175), vec2(-0.06, 0.175)));
        d = min(d, sdLine(uv, vec2(0.06, -0.175), vec2(0.06, 0.175)));
        float connector = random(vec2(seed, 5.5));
        if (connector > 0.3) d = min(d, sdLine(uv, vec2(-0.06, 0.0), vec2(0.06, 0.0)));
        if (connector > 0.6) d = min(d, sdLine(uv, vec2(-0.06, 0.1), vec2(0.06, -0.1)));
        if (connector > 0.8) d = min(d, sdLine(uv, vec2(-0.06, -0.1), vec2(0.06, 0.1)));
    } else if (s < 0.78) {
        d = min(d, sdLine(uv, vec2(-0.05, -0.175), vec2(-0.05, 0.175)));
        float side = random(vec2(seed, 6.6)) > 0.5 ? 1.0 : -1.0;
        
        d = min(d, sdLine(uv, vec2(-0.05, 0.175), vec2(0.075 * side, 0.075)));
        d = min(d, sdLine(uv, vec2(0.075 * side, 0.075), vec2(-0.05, 0.0)));
        
        if (random(vec2(seed, 6.7)) > 0.5) {
            d = min(d, sdLine(uv, vec2(-0.05, 0.0), vec2(0.075 * side, -0.075)));
            d = min(d, sdLine(uv, vec2(0.075 * side, -0.075), vec2(-0.05, -0.175)));
        }
    } else if (s < 0.9) {
        d = min(d, sdLine(uv, vec2(-0.125, -0.175), vec2(0.125, 0.175)));
        d = min(d, sdLine(uv, vec2(0.125, -0.175), vec2(-0.125, 0.175)));
        float extra = random(vec2(seed, 3.3));
        if (extra < 0.5) {
            d = min(d, sdLine(uv, vec2(-0.125, 0.0), vec2(0.125, 0.0)));
        } else {
            d = min(d, sdLine(uv, vec2(0.0, -0.175), vec2(0.0, 0.175)));
        }
    } else {
        vec2 p1 = vec2(0.0, 0.175), p2 = vec2(0.125, 0.0), p3 = vec2(0.0, -0.175), p4 = vec2(-0.125, 0.0);
        d = min(d, sdLine(uv, p1, p2));
        d = min(d, sdLine(uv, p2, p3));
        d = min(d, sdLine(uv, p3, p4));
        d = min(d, sdLine(uv, p4, p1));
        
        float inner = random(vec2(seed, 4.4));
        if (inner > 0.4) d = min(d, sdLine(uv, p1, p3));
        if (inner > 0.7) d = min(d, sdLine(uv, p2, p4));
        if (inner > 0.9) d = min(d, sdLine(uv, vec2(-0.175, 0.0), vec2(0.175, 0.0)));
    }
    
    return d;
}

// --- Aurora Borealis ---
vec3 aurora(vec2 uv, float vPos, float t) {
    vec3 auroraColor = vec3(0.0);
    
    // Transition distance widened for a softer "blur" effect on the top and bottom
    float verticalMask = smoothstep(0.0, 0.45, vPos) * smoothstep(1.0, 0.55, vPos);
    
    for (int i = 0; i < 2; i++) {
        float fi = float(i);
        float speed = 0.0035 + fi * 0.0014;
        float xScale = 1.0 + fi * 0.25;
        
        float shiftSpeed = 0.056 + fi * 0.028;
        
        vec2 auroraUV = vec2(uv.x * xScale + t * speed + fi * 5.0, uv.y * 1.76);
        
        // Use two noise layers with vertical drift to create pulsing highlight points
        float wave = noise(auroraUV * vec2(2.35, 0.70) + vec2(0.0, t * shiftSpeed));
        wave *= noise(auroraUV * vec2(1.17, 0.35) + vec2(t * shiftSpeed * 1.5, -t * shiftSpeed * 0.8));
        
        // Horizontal variation - stretched wavy curtains
        float horizWave = sin(uv.x * 3.53 + t * 0.315 + fi * 1.5) * 0.5 + 0.5;
        horizWave *= sin(uv.x * 1.47 - t * 0.168 + fi) * 0.4 + 0.6;
        
        float intensity = wave * verticalMask * horizWave;
        intensity = pow(max(intensity, 0.0), 1.2);
        
        float pulse = 0.85 + 0.15 * sin(t * 0.84 + fi * 2.0 + uv.x * 1.17);
        
        // Color gradient: green to cyan to purple, based on vertical position
        vec3 layerColor;
        float colorPhase = fi / 4.0 + vPos * 0.25;
        if (colorPhase < 0.33) {
            layerColor = mix(vec3(0.2, 0.9, 0.4), vec3(0.3, 1.0, 0.8), colorPhase * 3.0);
        } else if (colorPhase < 0.66) {
            layerColor = mix(vec3(0.3, 1.0, 0.8), vec3(0.6, 0.5, 1.0), (colorPhase - 0.33) * 3.0);
        } else {
            layerColor = mix(vec3(0.6, 0.5, 1.0), vec3(0.8, 0.3, 0.6), (colorPhase - 0.66) * 3.0);
        }
        
        // Increase base intensity and add a "white highlight" for high intensity points
        float highlight = pow(intensity, 4.0) * pulse * 0.8;
        auroraColor += (layerColor * intensity * pulse * 0.6) + vec3(highlight);
    }
    
    return auroraColor;
}

void main() {
    // --- Coordinates Setup (from reference) ---
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
    
    // Normalized vertical position for gradient and masks
    float verticalPos = clamp(texCoord0.y, 0.0, 1.0);
    
    // === LAYER 1: Base Sky Gradient ===
    vec3 skyTop = vec3(0.01, 0.01, 0.02);
    vec3 skyBottom = vec3(0.05, 0.03, 0.12);
    vec3 skyColor = mix(skyBottom, skyTop, verticalPos);
    fragColor = vec4(skyColor, 1.0);
    
    // === LAYER 2: Galactic Band / Nebula ===
    vec2 nebula_uv = zoomed_uv * 0.8 + (scrollPos * 0.005 * parallaxIntensity) / scale;
    float nebulaFbm = fbm(nebula_uv + vec2(0.0, 0.5), 3);
    float nebulaFbm2 = fbm(nebula_uv * 3.0 + vec2(50.0, 0.0), 2);
    
    float bandMask = smoothstep(0.15, 0.4, verticalPos) * smoothstep(0.85, 0.55, verticalPos);
    bandMask *= 0.7 + 0.3 * nebulaFbm2;
    
    vec3 nebulaColor1 = vec3(0.15, 0.08, 0.20);
    vec3 nebulaColor2 = vec3(0.12, 0.06, 0.16);
    vec3 nebulaColor = mix(nebulaColor1, nebulaColor2, nebulaFbm2);
    
    float roseMask = smoothstep(0.5, 0.7, nebulaFbm);
    nebulaColor += vec3(0.08, 0.02, 0.04) * roseMask;
    
    fragColor.rgb += nebulaColor * nebulaFbm * bandMask * 0.18;
    
    // === LAYER 3: Space Dust / Fog Wisps ===
    vec2 dust_uv = zoomed_uv * 6.0 + (scrollPos * 0.02 * parallaxIntensity) / scale;
    float dust = fbm(dust_uv + vec2(200.0, 100.0), 2);
    dust = smoothstep(0.45, 0.75, dust);
    
    vec3 dustColor = vec3(0.18, 0.22, 0.28);
    fragColor.rgb += dustColor * dust * 0.06;
    
    // === LAYER 4: Aurora Borealis ===
    // Synced with background layers using zoomed_uv and parallax
    vec2 aurora_uv = zoomed_uv + (scrollPos * 0.015 * parallaxIntensity) / scale;
    vec3 auroraLight = aurora(aurora_uv, verticalPos, time);
    fragColor.rgb += auroraLight * 1.1; // Increased light level
    
    // === LAYER 5: Star Field ===
    vec3 stars = vec3(0.0);
    
    // --- Distant small stars (many, slow parallax) ---
    for (float layer = 0.0; layer < 2.0; layer += 1.0) {
        float cellsize = 17.5 + layer * 7.5;
        float offset = random(vec2(layer + 10.0)) * 500.0;
        float parallaxMult = 15.0 + layer * 8.0;
        
        vec2 coord = zoomed_frag + vec2(offset) + (scrollPos * parallaxMult * parallaxIntensity) / scale;
        vec2 cell = floor(coord / cellsize);
        vec2 luv = fract(coord / cellsize);
        
        float starPresence = random(cell + vec2(3.0, 7.0));
        if (starPresence > 0.65) {
            vec2 starPos = vec2(random(cell), random(cell + vec2(11.0))) * 0.7 + 0.15;
            float d = length(luv - starPos) * cellsize;
            
            float twinkle = 0.85 + 0.15 * sin(time * 1.8 + random(cell) * 6.28);
            float brightness = smoothstep(0.9, 0.0, d) * twinkle;
            
            stars += vec3(0.5, 0.55, 0.6) * brightness * 0.35;
        }
    }
    
    // --- Medium stars ---
    for (float layer = 0.0; layer < 2.0; layer += 1.0) {
        float cellsize = 35.0 + layer * 12.5;
        float offset = random(vec2(layer + 20.0)) * 500.0;
        float parallaxMult = 35.0 + layer * 12.0;
        
        vec2 coord = zoomed_frag + vec2(offset) + (scrollPos * parallaxMult * parallaxIntensity) / scale;
        vec2 cell = floor(coord / cellsize);
        vec2 luv = fract(coord / cellsize);
        
        float starPresence = random(cell + vec2(13.0, 17.0));
        if (starPresence > 0.72) {
            vec2 starPos = vec2(random(cell + vec2(5.0)), random(cell + vec2(19.0))) * 0.6 + 0.2;
            float d = length(luv - starPos) * cellsize;
            
            float core = exp(-d * d * 1.6);
            float glow = 0.25 / (1.0 + d * d * 0.32);
            float twinkle = 0.8 + 0.2 * sin(time * 2.2 + random(cell + vec2(23.0)) * 6.28);
            float brightness = (core + glow) * twinkle;
            
            float colorSeed = random(cell + vec2(29.0));
            vec3 starColor = vec3(1.0, 1.0, 1.0);
            if (colorSeed < 0.18) {
                starColor = vec3(1.0, 0.9, 0.7);
            } else if (colorSeed > 0.82) {
                starColor = vec3(0.7, 0.85, 1.0);
            }
            
            stars += starColor * brightness * 0.32;
        }
    }
    
    // --- Bright stars (few, more parallax) ---
    for (float layer = 0.0; layer < 2.0; layer += 1.0) {
        float cellsize = 90.0 + layer * 40.0;
        float offset = random(vec2(layer + 30.0)) * 500.0;
        float parallaxMult = 55.0 + layer * 20.0;
        
        vec2 coord = zoomed_frag + vec2(offset) + (scrollPos * parallaxMult * parallaxIntensity) / scale;
        vec2 cell = floor(coord / cellsize);
        vec2 luv = fract(coord / cellsize);
        
        float starPresence = random(cell + vec2(31.0, 37.0));
        if (starPresence > 0.82) {
            vec2 starPos = vec2(random(cell + vec2(41.0)), random(cell + vec2(43.0))) * 0.5 + 0.25;
            float d = length(luv - starPos) * cellsize;
            
            float core = exp(-d * d * 1.0);
            float glow = 0.4 / (1.0 + d * d * 0.16);
            float twinkle = 0.65 + 0.35 * sin(time * 3.0 + random(cell + vec2(47.0)) * 6.28);
            float brightness = (core + glow) * twinkle;
            
            float colorSeed = random(cell + vec2(53.0));
            vec3 starColor = vec3(1.0, 1.0, 1.0);
            if (colorSeed < 0.15) {
                starColor = vec3(1.0, 0.9, 0.7);
            } else if (colorSeed > 0.85) {
                starColor = vec3(0.7, 0.85, 1.0);
            }
            
            stars += starColor * brightness * 0.5;
        }
    }
    
    fragColor.rgb += stars;
    
    // === LAYER 6: Magical Runes ===
    for (float i = 0.0; i < 2.0; i += 1.0) {
        float cellsize = 90.0 + i * 50.0;
        float parallaxMult = 20.0 + i * 15.0;
        
        vec2 coord = zoomed_frag + vec2(i * 500.0) + (scrollPos * parallaxMult * parallaxIntensity) / scale;
        vec2 cell = floor(coord / cellsize);
        vec2 luv = fract(coord / cellsize) - 0.5;
        
        float seed = random(cell + vec2(i * 13.5, 42.0));
        if (seed > 0.92) {
            float t = time * (0.15 + seed * 0.1) + seed * 62.8;
            float pulse = sin(t) * 0.5 + 0.5;
            float fadeInOut = smoothstep(0.0, 0.3, pulse) * smoothstep(1.0, 0.7, pulse);
            
            float grow = 0.5 + 0.5 * pulse;
            vec2 drift = vec2(sin(t * 0.4), cos(t * 0.6)) * 0.075;
            
            float initialRotation = random(cell + vec2(i * 13.5 + 1.2, 57.0)) * 2.0 * PI;
            float rotationSpeed = (random(cell + vec2(i * 13.5 + 2.1, 63.0)) - 0.5) * 0.15;
            float angle = initialRotation + time * rotationSpeed;
            float s = sin(angle), c = cos(angle);
            mat2 rot = mat2(c, -s, s, c);
            
            float runeScale = grow * 0.6;
            vec2 runeUV = ((luv - drift) / runeScale) * rot;
            float d = getRune(runeUV, seed);
            
            float thickness = 0.4 / (cellsize * runeScale);
            float runeVal = smoothstep(thickness, 0.0, d);
            float glow = exp(-d * 60.0) * 0.45;
            
            vec3 runeColor = mix(vec3(0.4, 0.7, 1.0), vec3(0.8, 0.4, 1.0), seed);
            if (seed > 0.98) runeColor = vec3(1.0, 0.9, 0.5);
            
            fragColor.rgb += runeColor * (runeVal + glow) * fadeInOut * 0.14;
        }
    }
    
    // === LAYER 7: Shooting Stars ===
    float shootingTotal = 0.0;
    for (float i = 0.0; i < 3.0; i += 1.0) {
        shootingTotal += shootingStar(texCoord0, time, i * 173.0 + 31.0);
    }
    fragColor.rgb += vec3(1.0, 0.97, 0.92) * shootingTotal * 0.4;
    
    fragColor = clamp(fragColor, 0.0, 1.0);
}

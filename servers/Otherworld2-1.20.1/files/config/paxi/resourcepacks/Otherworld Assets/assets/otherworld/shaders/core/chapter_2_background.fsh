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

// Rotational FBM for fluffy volumetric-looking clouds
float cloudDensity(vec2 p) {
    float n = 0.0;
    float amp = 0.5;
    mat2 rot = mat2(0.8, -0.6, 0.6, 0.8);
    for (int i = 0; i < 5; i++) {
        n += amp * noise(p);
        p = rot * p * 2.0 + vec2(100.0);
        amp *= 0.5;
    }
    return n;
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
    
    // === LAYER 1: Summer Sky Gradient ===
    // Deep vibrant blue to soft hazy cyan/peach near horizon
    vec3 skyTop = vec3(0.05, 0.35, 0.85);
    vec3 skyMid = vec3(0.25, 0.65, 0.90);
    vec3 skyBot = vec3(0.75, 0.85, 0.95); // Hazy horizon
    
    vec3 skyColor = mix(skyBot, skyMid, smoothstep(0.0, 0.4, verticalPos));
    skyColor = mix(skyColor, skyTop, smoothstep(0.4, 1.0, verticalPos));
    fragColor = vec4(skyColor, 1.0);
    
    // === LAYER 2: Sun & Optical Halos ===
    // Placed dynamically based on zoomed_uv so it scales properly but stays fixed relative to camera center
    vec2 sunPos = vec2(aspect * 0.75, 0.7); // Top right-ish
    vec2 toSun = normalize(sunPos - zoomed_uv);
    float dSun = length(zoomed_uv - sunPos);
    
    vec3 sunColor = vec3(1.0, 0.98, 0.85);
    float sunCore = exp(-dSun * 45.0);
    float sunGlow = exp(-dSun * 4.0) * 0.6;
    
    // Prismatic Halo
    float ringRadius = 0.4;
    float ringDist = abs(dSun - ringRadius);
    float sunRing = exp(-ringDist * 20.0) * 0.15;
    vec3 rainbow = 0.5 + 0.5 * cos(time * 0.2 + dSun * 15.0 + vec3(0, 2, 4));
    
    fragColor.rgb += sunColor * (sunCore + sunGlow) + rainbow * sunRing;
    
    // === LAYER 3: Aether Currents (Magic Wind) ===
    float aetherAlpha = 0.0;
    for(int i = 0; i < 2; i++) {
        float fi = float(i);
        vec2 w_uv = zoomed_uv * vec2(1.5, 2.0) + (scrollPos * 0.05 * parallaxIntensity) / scale;
        
        // Swooping curves
        w_uv.y += sin(w_uv.x * 2.5 - time * 0.4 + fi * PI) * 0.15;
        w_uv.y += fbm(w_uv * 2.0 - vec2(time * 0.1, 0.0), 2) * 0.1;
        w_uv.x -= time * (0.05 + fi * 0.02);
        
        float ribbonDist = abs(w_uv.y - 0.7 + fi * 0.1);
        float lineMask = 1.0 - smoothstep(0.0, 0.04, ribbonDist);
        float glowMask = exp(-ribbonDist * 15.0) * 0.3;
        
        float breakNoise = smoothstep(0.3, 0.7, fbm(w_uv * 4.0, 3));
        
        aetherAlpha += (lineMask + glowMask) * breakNoise;
    }
    vec3 aetherColor = vec3(0.3, 0.9, 1.0); // Cyan glowing magic
    fragColor.rgb += aetherColor * aetherAlpha * 0.7;

    // === LAYER 4: Cirrus Clouds (High Altitude Wisps) ===
    vec2 cirrus_uv = zoomed_uv * vec2(1.5, 3.5) + (scrollPos * 0.1 * parallaxIntensity) / scale;
    cirrus_uv.x -= time * 0.008;
    cirrus_uv.y += fbm(cirrus_uv * 0.5, 2) * 0.3; // wisp turbulence
    
    float c_cirrus = fbm(cirrus_uv, 4);
    float cirrus_alpha = smoothstep(0.45, 0.75, c_cirrus);
    
    // Deeper Volumetric Self Shadowing for Cirrus Clouds
    float c_cirrus_light = fbm(cirrus_uv + toSun * 0.02, 4);
    float cirrus_shadow = clamp((c_cirrus_light - c_cirrus) * 2.5, 0.0, 1.0);
    
    vec3 cirrusColorBase = mix(vec3(1.0, 0.9, 0.85), vec3(1.0, 0.98, 0.95), clamp(verticalPos * 1.5, 0.0, 1.0));
    vec3 cirrusShadowColor = vec3(0.70, 0.65, 0.75); // Soft shadowy pinkish-purple
    vec3 cirrusColor = mix(cirrusColorBase, cirrusShadowColor, cirrus_shadow);
    
    fragColor.rgb = mix(fragColor.rgb, cirrusColor, cirrus_alpha * 0.65);
    
    // === LAYER 5: Cumulonimbus (Giant Storm/Anvil Clouds in Background) ===
    vec2 cb_uv = zoomed_uv * 1.2 + (scrollPos * 0.3 * parallaxIntensity) / scale;
    cb_uv.x -= time * 0.01;
    
    // Anvil shaping (wider at top)
    float anvilShape = smoothstep(0.5, 0.8, cb_uv.y) * 0.25;
    cb_uv.x += fbm(cb_uv * 0.5, 2) * anvilShape;
    
    // Domain warp for organic edges
    vec2 cb_q = vec2(fbm(cb_uv, 3), fbm(cb_uv + vec2(3.1, 7.8), 3));
    float cb_n = cloudDensity(cb_uv + cb_q * 0.15 + vec2(10.0, 20.0));
    float cb_alpha = smoothstep(0.46 - anvilShape, 0.7, cb_n);
    
    // Deeper Volumetric Self Shadowing for Cumulonimbus
    float cb_light1 = cloudDensity(cb_uv + cb_q * 0.15 + vec2(10.0, 20.0) + toSun * 0.04);
    float cb_light2 = cloudDensity(cb_uv + cb_q * 0.15 + vec2(10.0, 20.0) + toSun * 0.08);
    float cb_shadow = clamp((cb_light1 - cb_n) * 3.0 + (cb_light2 - cb_n) * 1.5, 0.0, 1.0);
    
    // Fade near horizon so it feels massive but distant
    cb_alpha *= smoothstep(0.1, 0.35, verticalPos);
    
    vec3 cbLit = vec3(1.0, 0.95, 0.9);
    vec3 cbShadowColor = vec3(0.50, 0.45, 0.60); // Deeper purplish storm shadow for more depth
    vec3 cbColor = mix(cbLit, cbShadowColor, cb_shadow);
    
    // Rim light from sun
    float cbRim = exp(-dSun * 1.5) * cb_alpha * cb_shadow;
    cbColor += vec3(1.0, 0.8, 0.4) * cbRim;
    
    fragColor.rgb = mix(fragColor.rgb, cbColor, cb_alpha * 0.85);

    // === LAYER 6: Cumulus (Foreground Fluffy Clouds) ===
    vec2 cu_uv = zoomed_uv * 2.2 + (scrollPos * 0.8 * parallaxIntensity) / scale;
    cu_uv.x -= time * 0.02;
    
    // Domain warp for organic shapes
    vec2 q = vec2(fbm(cu_uv, 3), fbm(cu_uv + vec2(5.2, 1.3), 3));
    vec2 cu_p = cu_uv + q * 0.2;
    
    float cu_n = cloudDensity(cu_p);
    float cu_alpha = smoothstep(0.42, 0.65, cu_n);
    
    // Deeper Volumetric Shadow for Cumulus
    float cu_light1 = cloudDensity(cu_p + toSun * 0.03);
    float cu_light2 = cloudDensity(cu_p + toSun * 0.06);
    float cu_shadow = clamp((cu_light1 - cu_n) * 3.5 + (cu_light2 - cu_n) * 1.5, 0.0, 1.0);
    
    // Floating mid-sky constraint (flatter bottoms)
    float cuBotMask = smoothstep(0.15, 0.3, verticalPos);
    float cuTopMask = 1.0 - smoothstep(0.6, 0.9, verticalPos);
    cu_alpha *= cuBotMask * cuTopMask;
    
    vec3 cuLit = vec3(1.0, 0.98, 0.95);
    vec3 cuShadowColor = vec3(0.60, 0.70, 0.85); // Deeper blue shadow for volume
    vec3 cuColorFinal = mix(cuLit, cuShadowColor, cu_shadow);
    
    // Brighten clouds near the sun
    cuColorFinal += vec3(1.0, 0.9, 0.6) * exp(-dSun * 2.5) * cu_alpha * 0.6;
    
    fragColor.rgb = mix(fragColor.rgb, cuColorFinal, cu_alpha * 0.95);
    
    // === LAYER 7: Morning/Summer Fog (Low Ground) ===
    vec2 fog_uv = zoomed_uv * vec2(1.5, 4.0) + (scrollPos * 1.5 * parallaxIntensity) / scale;
    fog_uv.x -= time * 0.025;
    float fogNoise = fbm(fog_uv + vec2(time * 0.01, 0.0), 3);
    
    float fogHeight = 0.15 + fogNoise * 0.15;
    float fogAlpha = 1.0 - smoothstep(fogHeight - 0.15, fogHeight, verticalPos);
    fogAlpha *= smoothstep(0.3, 0.7, fogNoise);
    
    vec3 fogColorBase = vec3(0.85, 0.92, 0.95);
    fragColor.rgb = mix(fragColor.rgb, fogColorBase, fogAlpha * 0.7);

    // === LAYER 8: Volumetric Light Shafts (Sun Rays) ===
    float angle = atan(zoomed_uv.y - sunPos.y, zoomed_uv.x - sunPos.x);
    float rayNoise = fbm(vec2(angle * 5.0, time * 0.05), 2);
    float rayNoise2 = fbm(vec2(angle * 12.0 - time * 0.02, 0.0), 2);
    
    float shafts = smoothstep(0.4, 0.8, rayNoise * 0.7 + rayNoise2 * 0.3);
    shafts *= exp(-dSun * 1.2); // Fade out over distance
    
    vec3 shaftColor = mix(vec3(1.0, 0.9, 0.6), vec3(0.6, 0.8, 1.0), sin(angle * 3.0 + time) * 0.5 + 0.5);
    fragColor.rgb += shaftColor * shafts * 0.35;

    // --- Post Processing ---
    // Subtle Vignette
    vec2 uvNorm = texCoord0;
    float distEdge = distance(uvNorm, vec2(0.5));
    float vignette = 1.0 - smoothstep(0.2, 0.9, distEdge);
    vec3 vignetteColor = mix(vec3(0.3, 0.4, 0.5), vec3(1.0), vignette);
    fragColor.rgb *= vignetteColor;
    
    // Contrast curve to make the sky and clouds pop
    fragColor.rgb = mix(vec3(0.5), fragColor.rgb, 1.15);
    fragColor.rgb = clamp(fragColor.rgb, 0.0, 1.0);
}
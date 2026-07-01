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

// --- Fluid Dynamics (Fire & Ice) ---
float fbmFluidFire(vec2 uv, float t) {
    // Deep rolling domain warp for fire
    vec2 q = vec2(fbm(uv + t * 0.2, 3), fbm(uv + vec2(5.2, 1.3) - t * 0.25, 3));
    vec2 r = vec2(fbm(uv + 4.0 * q + vec2(1.7, 9.2) + t * 0.3, 3), fbm(uv + 4.0 * q + vec2(8.3, 2.8) - t * 0.2, 3));
    // Stretch the warp vertically to make the noise behave more like rising flames
    return fbm(uv + 4.0 * r * vec2(0.5, 1.2), 4);
}

float fbmFluidIce(vec2 uv, float t) {
    // Cloudy billowy domain warp for blizzard breath
    vec2 q = vec2(fbm(uv + t * 0.2, 3), fbm(uv + vec2(2.1, 4.3) + t * 0.15, 3));
    return fbm(uv + 3.0 * q, 4); 
}

// --- Lightning Arc ---
float lightningArc(vec2 uv, vec2 a, vec2 b, float t, float scale) {
    vec2 pa = uv - a;
    vec2 ba = b - a;
    float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    
    // Add jagged high-frequency noise to the line
    float n = fbm(vec2(h * 15.0, t * 5.0), 3) - 0.5;
    n += (fbm(vec2(h * 35.0, -t * 8.0), 2) - 0.5) * 0.5;
    
    // Taper at the ends so it connects properly
    n *= smoothstep(0.0, 0.05, h) * smoothstep(1.0, 0.95, h);
    
    vec2 perp = normalize(vec2(-ba.y, ba.x));
    // Displace line based on noise
    vec2 d = pa - ba * h + perp * n * length(ba) * 0.15; 
    
    float dist = length(d);
    // Scale distance to keep stroke width consistent when zooming out
    float scaledDist = dist * scale;
    
    float core = exp(-scaledDist * 150.0);
    float glow = 0.3 / (1.0 + scaledDist * 15.0);
    
    return core + glow;
}

// --- Particles (Sparks & Frost Shards) ---
vec3 particles(vec2 fragCoord, float t, vec2 scroll, float scale, float mask, vec3 colBase, vec3 colHighlight, vec2 dir, float seedOffset) {
    vec3 pCol = vec3(0.0);
    for (float layer = 0.0; layer < 2.0; layer += 1.0) {
        float cellsize = 60.0 + layer * 30.0;
        float parallaxMult = 15.0 + layer * 10.0;
        
        vec2 coord = fragCoord + vec2(layer * 150.0 + seedOffset) + (scroll * parallaxMult * parallaxIntensity) / scale;
        
        // Move opposite to 'dir' so visuals move in 'dir' direction
        coord -= dir * t * (60.0 + layer * 30.0);
        // Swirling drift
        coord.x += sin(t * 2.0 + layer) * 20.0; 
        
        vec2 cell = floor(coord / cellsize);
        vec2 luv = fract(coord / cellsize) - 0.5;
        
        float presence = random(cell + vec2(seedOffset, 11.2));
        if (presence > 0.85) {
            vec2 pos = vec2((random(cell + 1.0) - 0.5) * 0.8, (random(cell + 2.0) - 0.5) * 0.8);
            
            pos.x += sin(t * 8.0 + random(cell) * 6.28) * 0.05; // Fast jitter
            
            float d = length(luv - pos) * cellsize;
            float core = exp(-d * d * 10.0);
            float glow = 0.6 / (1.0 + d * d * 0.5);
            float pulse = 0.5 + 0.5 * sin(t * 12.0 + random(cell + 4.0) * 6.28); // Flicker
            
            vec3 color = colBase;
            if (random(cell + 5.0) > 0.7) color = colHighlight;
            
            pCol += color * (core + glow) * pulse * mask;
        }
    }
    return pCol;
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
    
    // === LAYER 1: Deep Storm Background ===
    vec3 stormBase = vec3(0.02, 0.01, 0.03);
    vec3 stormClouds = vec3(0.06, 0.05, 0.12); // Bruised dark purple storm
    vec3 stormBg = mix(stormBase, stormClouds, fbm(zoomed_uv * 1.5 + time * 0.05, 3));
    fragColor = vec4(stormBg, 1.0);
    
    // === MASKING THE BATTLEFIELD ===
    // Apply a global time slow-down
    float slowTime = time * 0.33; 

    // Creates a dynamic diagonal front where Fire (Bottom-Left) meets Ice (Top-Right)
    float turb = fbm(zoomed_uv * 1.5 - slowTime * 0.15, 3) * 2.0 - 1.0;
    float clashLine = (zoomed_uv.x - aspect * 0.5) + (zoomed_uv.y - 0.5) * 0.8 + turb * 0.7;
    
    // Scale the blend width based on zoom (1.0/scale) so the gradient stays wide when zoomed out
    float blendWidth = 0.4 / scale; 
    
    float fireMask = smoothstep(blendWidth, -blendWidth, clashLine);
    float iceMask = smoothstep(-blendWidth, blendWidth, clashLine);
    
    // Clash zone is the highly turbulent, middle overlapping region
    float clashZone = smoothstep(blendWidth * 2.0, 0.0, abs(clashLine)); 
    
    // === LAYER 2: Dragonfire (Inferno) ===
    // Restored correct slow inward flow direction
    vec2 fire_uv1 = zoomed_uv * 1.8 + vec2(-slowTime * 0.4, -slowTime * 0.3) + (scrollPos * 0.02 * parallaxIntensity) / scale;
    vec2 fire_uv2 = zoomed_uv * 2.5 + vec2(-slowTime * 0.6, -slowTime * 0.5) + (scrollPos * 0.03 * parallaxIntensity) / scale;
    vec2 smoke_uv = zoomed_uv * 1.5 + vec2(-slowTime * 0.2, -slowTime * 0.1) + (scrollPos * 0.01 * parallaxIntensity) / scale;

    float fireVal1 = fbmFluidFire(fire_uv1, slowTime * 0.8);
    float fireVal2 = fbmFluidFire(fire_uv2, slowTime * 1.2);
    float smokeVal = fbm(smoke_uv + vec2(slowTime * 0.5), 4);

    float fireMix = max(fireVal1 * 0.9, fireVal2 * 0.7);
    
    // Construct rich reds, oranges, and yellows
    vec3 fCol = mix(vec3(0.5, 0.0, 0.0), vec3(0.9, 0.2, 0.0), smoothstep(0.2, 0.5, fireMix)); // Deep red to bright red
    fCol = mix(fCol, vec3(1.0, 0.5, 0.0), smoothstep(0.5, 0.7, fireMix)); // Red to orange
    fCol = mix(fCol, vec3(1.0, 0.9, 0.2), smoothstep(0.7, 0.85, fireMix)); // Orange to yellow
    fCol += vec3(1.0, 1.0, 0.9) * smoothstep(0.85, 1.0, fireMix); // White hot core

    // Dark grey/black smoke
    vec3 smokeColor = mix(vec3(0.01), vec3(0.15, 0.15, 0.15), smoothstep(0.3, 0.7, smokeVal));
    
    // Blend smoke and fire - fire punches through smoke
    vec3 finalFire = mix(smokeColor, fCol, smoothstep(0.35, 0.6, fireMix));

    fragColor.rgb += finalFire * fireMask * 1.5;
    
    // === LAYER 3: Frost Breath (Blizzard) ===
    // Restored slow inward flow direction, multiple depth layers for cloudy breath
    vec2 ice_uv1 = zoomed_uv * 2.0 + vec2(slowTime * 0.3, slowTime * 0.25) + (scrollPos * 0.02 * parallaxIntensity) / scale;
    vec2 ice_uv2 = zoomed_uv * 3.5 + vec2(slowTime * 0.4, slowTime * 0.35) + (scrollPos * 0.03 * parallaxIntensity) / scale;
    vec2 ice_uv3 = zoomed_uv * 5.0 + vec2(slowTime * 0.5, slowTime * 0.45) + (scrollPos * 0.04 * parallaxIntensity) / scale;

    float ice1 = fbmFluidIce(ice_uv1, slowTime * 0.5);
    float ice2 = fbmFluidIce(ice_uv2, slowTime * 0.8);
    float ice3 = fbmFluidIce(ice_uv3, slowTime * 1.1);

    // Combine softly for a cloudy volume
    float iceVal = ice1 * 0.5 + ice2 * 0.3 + ice3 * 0.2;
    
    // Deep icy blues transitioning to cyan, less washed out
    vec3 deepIce = mix(vec3(0.01, 0.02, 0.05), vec3(0.05, 0.2, 0.5), smoothstep(0.1, 0.4, iceVal));
    vec3 iceColor = mix(deepIce, vec3(0.2, 0.6, 0.9), smoothstep(0.4, 0.65, iceVal));
    iceColor = mix(iceColor, vec3(0.6, 0.9, 1.0), smoothstep(0.65, 0.85, iceVal));
    iceColor += vec3(0.8, 0.95, 1.0) * smoothstep(0.85, 1.0, iceVal) * 0.8; // Tight white highlights
    
    fragColor.rgb += iceColor * iceMask * 1.5;
    
    // === LAYER 4: The Infusion Clash (Vapor/Energy) ===
    // A highly bright reactive zone where they meet
    float sparkNoise = fbm(vec2(clashLine * 8.0, slowTime * 4.0), 2);
    vec3 clashEnergy = vec3(0.8, 0.4, 1.0) * smoothstep(0.5, 0.9, sparkNoise) * clashZone * 2.0; // Electric purple energy
    fragColor.rgb += clashEnergy;
    
    // === LAYER 5: Lightning Strikes ===
    float bolt = 0.0;
    float flashTime = slowTime * 2.5; // Slow down strike intervals
    float lseed = floor(flashTime);
    float localTime = fract(flashTime);
    
    // Electric strobe envelope: fast strike, quick strobe, rapid fade
    float flashEnvelope = exp(-localTime * 8.0) * (0.8 + 0.2 * sin(localTime * 40.0));
    
    if (random(vec2(lseed, 1.0)) > 0.4) { // 60% chance to strike per interval
        // Striking down across the clash zone
        vec2 start = vec2(aspect * 0.5 + turb + (random(vec2(lseed, 2.0))-0.5)*2.0, 1.2);
        vec2 end = vec2(aspect * 0.5 - turb + (random(vec2(lseed, 3.0))-0.5)*2.0, -0.2);
        
        // Pass the zoom scale to the lightning so the stroke scales correctly
        bolt += lightningArc(zoomed_uv, start, end, slowTime, scale);
        
        // Add random branching
        if (random(vec2(lseed, 4.0)) > 0.4) {
            vec2 mid = mix(start, end, 0.4 + (random(vec2(lseed, 5.0))-0.5)*0.3);
            vec2 branchEnd = mid + vec2((random(vec2(lseed, 6.0))-0.5)*1.5, -0.4);
            bolt += lightningArc(zoomed_uv, mid, branchEnd, slowTime + 0.1, scale);
        }
    }
    
    bolt *= flashEnvelope; // Apply the strobe/fade
    
    vec3 lightningColor = vec3(0.9, 0.7, 1.0); // Bright violet/white
    fragColor.rgb += lightningColor * bolt * 3.0;
    
    // Global atmospheric flash from the lightning illuminating the clouds
    float flashInt = bolt * 0.15;
    fragColor.rgb += vec3(0.6, 0.4, 0.9) * flashInt;
    
    // === LAYER 6: Flying Embers & Frost Shards ===
    // Fire Embers blowing Up-Right into the clash
    vec3 embers = particles(zoomed_frag, slowTime, scrollPos, scale, fireMask * 1.5, vec3(1.0, 0.4, 0.0), vec3(1.0, 0.9, 0.2), vec2(1.0, 1.0), 100.0);
    // Frost Shards blowing Down-Left into the clash
    vec3 shards = particles(zoomed_frag, slowTime, scrollPos, scale, iceMask * 1.5, vec3(0.2, 0.8, 1.0), vec3(1.0, 1.0, 1.0), vec2(-1.0, -1.0), 200.0);
    
    fragColor.rgb += embers + shards;
    
    // --- Post Processing ---
    // Cinematic Vignette
    vec2 uvNorm = texCoord0;
    float distEdge = distance(uvNorm, vec2(0.5));
    float vignette = 1.0 - smoothstep(0.3, 0.9, distEdge);
    vec3 vignetteColor = mix(vec3(0.05, 0.02, 0.08), vec3(1.0), vignette); // Deep purple shadow
    fragColor.rgb *= vignetteColor;
    
    // Contrast boost to make the elements pop against the storm
    fragColor.rgb = mix(vec3(0.02), fragColor.rgb, 1.2);
    
    fragColor = clamp(fragColor, 0.0, 1.0);
}

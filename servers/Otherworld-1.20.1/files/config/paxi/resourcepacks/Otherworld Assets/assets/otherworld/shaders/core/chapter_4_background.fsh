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

// --- SDF Helpers ---
float sdLine(vec2 p, vec2 a, vec2 b) {
    vec2 pa = p - a, ba = b - a;
    float h = clamp(dot(pa, ba) / max(dot(ba, ba), 0.0001), 0.0, 1.0);
    return length(pa - ba * h);
}

float sdBox( vec2 p, vec2 b ) {
    vec2 d = abs(p)-b;
    return length(max(d,0.0)) + min(max(d.x,d.y),0.0);
}

// --- RELIC / AUTOMATA GEN ---
float relicStructure(vec2 uv, float seed, float t) {
    float d = 100.0;
    float r = length(uv);
    float a = atan(uv.y, uv.x);
    
    // Slow down relic gear dashes and spokes globally
    float slowTime = t * 0.2;
    
    float numRings = 4.0 + floor(random(vec2(seed, 1.0)) * 3.0);
    for(float i=1.0; i<=7.0; i+=1.0) {
        if (i > numRings) break;
        
        float ringR = 0.15 * i + random(vec2(seed, i)) * 0.1;
        float ringThickness = 0.005 + random(vec2(seed, i+10.0)) * 0.015;
        
        // Broken rings (slowed down dash speed)
        float dashSpeed = (random(vec2(seed, i+20.0)) - 0.5) * 2.0;
        float dashFreq = floor(4.0 + random(vec2(seed, i+30.0)) * 8.0);
        float dashes = sin(a * dashFreq + slowTime * dashSpeed);
        
        float ringDist = abs(r - ringR);
        
        // Create segmented gear teeth on some rings
        if (random(vec2(seed, i+50.0)) > 0.6) {
            float teeth = sin(a * floor(20.0 + random(vec2(seed, i)) * 20.0));
            ringDist += smoothstep(0.0, 0.5, teeth) * 0.015;
        }
        
        if (dashes > -0.2 || random(vec2(seed, i+40.0)) > 0.6) {
            d = min(d, ringDist - ringThickness);
        }
    }
    
    // Add intersecting spokes (slowed down)
    float numSpokes = floor(3.0 + random(vec2(seed, 99.0)) * 5.0);
    float spokeA = sin(a * numSpokes + slowTime * 0.1);
    float spokeDist = abs(spokeA) * r;
    // only show spokes within outer ring
    float outerR = 0.15 * numRings + 0.1;
    if (r < outerR && random(vec2(seed, 100.0)) > 0.4) {
        d = min(d, spokeDist - 0.005);
    }
    
    return d;
}

// --- NEXUS WHISPERS ---
float getNexusRune(vec2 uv, float seed) {
    float d = 100.0;
    
    // Base square or diamond
    if (random(vec2(seed, 1.0)) > 0.5) {
        d = min(d, sdBox(uv, vec2(0.15)));
        // cut out center
        d = max(d, -(sdBox(uv, vec2(0.08))));
    } else {
        vec2 d_uv = vec2(uv.x + uv.y, uv.x - uv.y) * 0.707;
        d = min(d, sdBox(d_uv, vec2(0.15)));
        d = max(d, -(sdBox(d_uv, vec2(0.08))));
    }
    
    // Add center dot or line
    if (random(vec2(seed, 2.0)) > 0.5) {
        d = min(d, length(uv) - 0.04);
    } else {
        d = min(d, sdLine(uv, vec2(0.0, -0.1), vec2(0.0, 0.1)));
    }
    
    // Outer circuitry
    if (random(vec2(seed, 3.0)) > 0.5) {
        d = min(d, sdLine(uv, vec2(0.0, 0.15), vec2(0.0, 0.3)));
    }
    if (random(vec2(seed, 4.0)) > 0.5) {
        d = min(d, sdLine(uv, vec2(-0.15, 0.0), vec2(-0.3, 0.0)));
    }
    
    return d;
}

// Vertical streams of nexus whispers
vec3 nexusStreams(vec2 fragCoord, float t, vec2 scroll, float scale) {
    vec3 streams = vec3(0.0);
    
    // Slow down the entire stream progression
    float slowTime = t * 0.2;
    
    for(float layer = 0.0; layer < 3.0; layer += 1.0) {
        float cellsize = 60.0 + layer * 30.0; // columns
        float parallaxMult = 10.0 + layer * 8.0;
        
        vec2 coord = fragCoord + vec2(layer * 123.0) + (scroll * parallaxMult * parallaxIntensity) / scale;
        
        // Rise up slower
        coord.y -= slowTime * (30.0 + layer * 15.0);
        
        // Define columns
        vec2 cell = floor(coord / cellsize);
        vec2 luv = fract(coord / cellsize) - 0.5;
        
        // Only some columns have streams
        if (random(vec2(cell.x, layer)) > 0.6) {
            // Generate rune based on Y cell
            float seed = random(cell);
            
            // Fading trail effect
            // Add a slow pulse to the whole column
            float colPulse = sin(slowTime * 2.0 + cell.x * 10.0) * 0.5 + 0.5;
            
            // And individual rune brightness
            float runePulse = sin(slowTime * 5.0 + seed * 10.0) * 0.5 + 0.5;
            
            float d = getNexusRune(luv * 1.5, seed); // scale up uv slightly to make runes fit
            float thickness = 1.5 / cellsize;
            float val = smoothstep(thickness, 0.0, d);
            float glow = exp(-d * 20.0) * 0.5;
            
            vec3 color = mix(vec3(0.0, 0.8, 1.0), vec3(1.0, 0.7, 0.2), random(vec2(cell.x, 9.9))); // Cyan or Amber
            
            // Fade in/out sporadically to simulate "whispers"
            float visibility = smoothstep(0.4, 0.8, noise(vec2(cell.y * 0.2, slowTime * 0.5 + cell.x)));
            
            streams += color * (val + glow) * runePulse * visibility * colPulse * 0.8;
        }
    }
    return streams;
}

// --- DUST SPARKS ---
vec3 dustSparks(vec2 fragCoord, float t, vec2 scroll, float scale) {
    vec3 sparks = vec3(0.0);
    
    // Slow down the sparks
    float slowTime = t * 0.2;
    
    for (float layer = 0.0; layer < 2.0; layer += 1.0) {
        float cellsize = 80.0 + layer * 40.0;
        float parallaxMult = 20.0 + layer * 15.0;
        
        vec2 coord = fragCoord + vec2(layer * 200.0) + (scroll * parallaxMult * parallaxIntensity) / scale;
        
        // Rise up slower
        coord.y -= slowTime * (40.0 + layer * 20.0);
        coord.x += sin(slowTime * 1.0 + layer * 2.0) * 20.0; // Swirling heat
        
        vec2 cell = floor(coord / cellsize);
        vec2 luv = fract(coord / cellsize) - 0.5;
        
        float sparkPresence = random(cell + vec2(15.3, 11.2));
        if (sparkPresence > 0.85) {
            vec2 pos = vec2((random(cell + 1.0) - 0.5) * 0.8, (random(cell + 2.0) - 0.5) * 0.8);
            
            // Slower wobble
            pos.x += sin(slowTime * 5.0 + random(cell) * 6.28) * 0.05;
            
            float d = length(luv - pos) * cellsize;
            
            float core = exp(-d * d * 8.0);
            float glow = 0.5 / (1.0 + d * d * 0.5);
            float pulse = 0.5 + 0.5 * sin(slowTime * 8.0 + random(cell + 4.0) * 6.28);
            
            // Colors: Cyan, Gold, Orange
            vec3 color = vec3(1.0, 0.6, 0.1); // Spark orange
            if (random(cell + 5.0) > 0.5) {
                color = vec3(0.1, 0.8, 1.0); // Nexus cyan
            } else if (random(cell + 6.0) > 0.8) {
                color = vec3(1.0, 0.9, 0.3); // Bright gold
            }
            
            sparks += color * (core + glow) * pulse * 0.8;
        }
    }
    return sparks;
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
    
    // === LAYER 1: Deep Cavern Background ===
    // Dark brown/bronze at top, fading to a deep glowing cyan/amber at the bottom
    vec3 skyTop = vec3(0.05, 0.04, 0.03); // Deep stone/bronze
    vec3 skyMid = vec3(0.08, 0.05, 0.04); // Lighter earth
    vec3 skyBot = vec3(0.02, 0.15, 0.20); // Deep cyan nexus glow
    
    vec3 skyColor = mix(skyMid, skyBot, smoothstep(0.4, 1.0, verticalPos));
    skyColor = mix(skyTop, skyColor, smoothstep(0.0, 0.4, verticalPos));
    fragColor = vec4(skyColor, 1.0);
    
    // === LAYER 2: Ancient Nexus Energy / Light beams from below ===
    float beams = fbm(zoomed_uv * vec2(2.0, 0.5) + vec2(time * 0.01, 0.0), 3); // Slowed down 80%
    float beamMask = smoothstep(0.0, 1.0, verticalPos);
    fragColor.rgb += vec3(0.1, 0.4, 0.5) * beams * beamMask * 0.3;
    
    // === LAYER 3: Giant Relics ===
    vec3 relics = vec3(0.0);
    // Slow down relic macro movements
    float slowTime = time * 0.2; 
    
    for (float i = 0.0; i < 3.0; i += 1.0) {
        float parallaxMult = 2.0 + i * 2.0;
        vec2 r_uv = zoomed_uv * (1.0 + i * 0.5) + (scrollPos * parallaxMult * parallaxIntensity) / scale;
        
        // Shift centers (slowed down wobble)
        vec2 rcenter = vec2(aspect * (0.2 + i * 0.4), 0.3 + sin(slowTime * 0.05 + i) * 0.1 + i * 0.2); 
        vec2 p = r_uv - rcenter;
        
        // Rotate slowly (slowed down)
        float angle = slowTime * (0.05 + i * 0.02) * (i > 0.5 ? -1.0 : 1.0);
        float s = sin(angle), c = cos(angle);
        p = mat2(c, -s, s, c) * p;
        
        // Use full time to pass down, but we slowed down the inside of relicStructure
        float d = relicStructure(p, i * 12.3 + 4.0, time);
        
        float thickness = 0.005;
        float val = smoothstep(thickness, 0.0, d);
        float glow = exp(-d * 20.0) * 0.4;
        
        // Gold and Cyan
        vec3 color = mix(vec3(0.8, 0.5, 0.1), vec3(0.1, 0.6, 0.8), i / 2.0); 
        
        // Add distance fade and depth fade
        float fade = exp(-length(p) * 1.5) * (0.3 + 0.2 * i);
        
        relics += color * (val + glow) * fade;
    }
    fragColor.rgb += relics;
    
    // === LAYER 4: Whispers of the Nexus (Data Streams) ===
    vec3 streams = nexusStreams(zoomed_frag, time, scrollPos, scale);
    fragColor.rgb += streams;
    
    // === LAYER 5: Deep Earth Fog / Steam ===
    vec2 fog_uv = zoomed_uv * vec2(1.5, 2.0) + (scrollPos * 10.0 * parallaxIntensity) / scale;
    fog_uv.x += time * 0.02; // Keeping fog speed mostly the same as requested, slightly slow horizontal
    float fogNoise = fbm(fog_uv + vec2(time * 0.03, -time * 0.05), 3);
    float fogAlpha = smoothstep(0.4, 0.8, fogNoise);
    // Stronger at bottom
    fogAlpha *= smoothstep(0.2, 0.9, verticalPos);
    vec3 fogColor = vec3(0.1, 0.3, 0.35); // Cyan steam
    fragColor.rgb += fogColor * fogAlpha * 0.5;

    // === LAYER 6: Relic Sparks / Dust ===
    vec3 sparks = dustSparks(zoomed_frag, time, scrollPos, scale);
    fragColor.rgb += sparks;
    
    // --- Post Processing ---
    // Deep Subterranean Vignette
    vec2 uvNorm = texCoord0;
    float distEdge = distance(uvNorm, vec2(0.5, 0.3)); // center vignette slightly higher up
    float vignette = 1.0 - smoothstep(0.3, 0.9, distEdge);
    vec3 vignetteColor = mix(vec3(0.05, 0.02, 0.01), vec3(1.0), vignette); // dark warm earth tone shadow
    fragColor.rgb *= vignetteColor;
    
    // Contrast boost
    fragColor.rgb = mix(vec3(0.05), fragColor.rgb, 1.15);
    
    fragColor = clamp(fragColor, 0.0, 1.0);
}

#version 330

uniform mat4 ModelViewMat;
uniform mat4 ProjMat;
uniform vec2 size;
uniform float time;
uniform float zoom;
uniform vec2 scrollOffset;
uniform vec2 scrollSize;

in vec2 texCoord0;
out vec4 fragColor;

// Simplex 3D Noise 
// by Ian McEwan, Ashima Arts
vec4 permute(vec4 x){return mod(((x*34.0)+1.0)*x, 289.0);}
vec4 taylorInvSqrt(vec4 r){return 1.79284291400159 - 0.85373472095314 * r;}

float snoise(vec3 v){ 
  const vec2  C = vec2(1.0/6.0, 1.0/3.0) ;
  const vec4  D = vec4(0.0, 0.5, 1.0, 2.0);

  vec3 i  = floor(v + dot(v, C.yyy) );
  vec3 x0 = v - i + dot(i, C.xxx) ;

  vec3 g = step(x0.yzx, x0.xyz);
  vec3 l = 1.0 - g;
  vec3 i1 = min( g.xyz, l.zxy );
  vec3 i2 = max( g.xyz, l.zxy );

  vec3 x1 = x0 - i1 + 1.0 * C.xxx;
  vec3 x2 = x0 - i2 + 2.0 * C.xxx;
  vec3 x3 = x0 - 1.0 + 3.0 * C.xxx;

  i = mod(i, 289.0 ); 
  vec4 p = permute( permute( permute( 
             i.z + vec4(0.0, i1.z, i2.z, 1.0 ))
           + i.y + vec4(0.0, i1.y, i2.y, 1.0 )) 
           + i.x + vec4(0.0, i1.x, i2.x, 1.0 ));

  float n_ = 1.0/7.0;
  vec3  ns = n_ * D.wyz - D.xzx;

  vec4 j = p - 49.0 * floor(p * ns.z *ns.z);

  vec4 x_ = floor(j * ns.z);
  vec4 y_ = floor(j - 7.0 * x_ );

  vec4 x = x_ *ns.x + ns.yyyy;
  vec4 y = y_ *ns.x + ns.yyyy;
  vec4 h = 1.0 - abs(x) - abs(y);

  vec4 b0 = vec4( x.xy, y.xy );
  vec4 b1 = vec4( x.zw, y.zw );

  vec4 s0 = floor(b0)*2.0 + 1.0;
  vec4 s1 = floor(b1)*2.0 + 1.0;
  vec4 sh = -step(h, vec4(0.0));

  vec4 a0 = b0.xzyw + s0.xzyw*sh.xxyy ;
  vec4 a1 = b1.xzyw + s1.xzyw*sh.zzww ;

  vec3 p0 = vec3(a0.xy,h.x);
  vec3 p1 = vec3(a0.zw,h.y);
  vec3 p2 = vec3(a1.xy,h.z);
  vec3 p3 = vec3(a1.zw,h.w);

  vec4 norm = taylorInvSqrt(vec4(dot(p0,p0), dot(p1,p1), dot(p2, p2), dot(p3,p3)));
  p0 *= norm.x;
  p1 *= norm.y;
  p2 *= norm.z;
  p3 *= norm.w;

  vec4 m = max(0.5 - vec4(dot(x0,x0), dot(x1,x1), dot(x2,x2), dot(x3,x3)), 0.0);
  m = m * m;
  return 105.0 * dot( m*m, vec4( dot(p0,x0), dot(p1,x1), 
                                dot(p2,x2), dot(p3,x3) ) );
}

float fbm3(vec3 p) {
    float f = 0.0;
    float amp = 0.5;
    for(int i = 0; i < 3; i++) {
        f += amp * snoise(p);
        p.xy = mat2(1.6, -1.2, 1.2, 1.6) * p.xy;
        p.z *= 1.2;
        amp *= 0.5;
    }
    return f * 0.5 + 0.5;
}

float fbm2(vec3 p) {
    float f = 0.5 * snoise(p);
    p.xy = mat2(1.6, -1.2, 1.2, 1.6) * p.xy;
    p.z *= 1.2;
    f += 0.25 * snoise(p);
    return f * 0.5 + 0.5;
}

vec3 getLavaColor(float h) {
    vec3 core   = vec3(0.04, 0.02, 0.015);
    vec3 crims  = vec3(0.50, 0.05, 0.02);
    vec3 orange = vec3(0.90, 0.35, 0.05);
    vec3 gold   = vec3(1.00, 0.75, 0.20);
    vec3 white  = vec3(1.00, 0.95, 0.85);

    vec3 col = mix(core, crims, smoothstep(0.05, 0.35, h));
    col = mix(col, orange, smoothstep(0.35, 0.65, h));
    col = mix(col, gold, smoothstep(0.60, 0.85, h));
    col = mix(col, white, smoothstep(0.80, 1.0, h));
    return col;
}

void main() {
    float aspect = size.x / max(size.y, 1.0);
    vec2 p = texCoord0 * 2.0 - 1.0;
    p.x *= aspect;

    vec2 scrollPos = vec2(0.0);
    if (scrollSize.x > 0.0) scrollPos.x = scrollOffset.x / scrollSize.x;
    if (scrollSize.y > 0.0) scrollPos.y = scrollOffset.y / scrollSize.y;
    
    // Subtle parallax depth
    p += scrollPos * 0.4;

    float t = time * 0.066;

    // 1. Deep Layer: massive, barely shifting tectonic glow
    vec3 pDeep = vec3(p * 1.2, t * 0.2);
    pDeep.y -= t * 0.1; // moving upward
    float nDeep = fbm3(pDeep);
    float baseGlow = smoothstep(0.2, 0.8, nDeep);

    // 2. Mid Layer: molten channels crawling slowly upward
    vec3 pMid = vec3(p * 2.5, t * 0.4);
    pMid.y -= t * 0.5;
    
    // Domain warp for fluid, organic vein-like movement
    vec3 warp = vec3(
        snoise(pMid + vec3(1.0, 2.0, t * 0.5)),
        snoise(pMid + vec3(-2.0, 4.0, -t * 0.5)),
        0.0
    );
    float nMid = fbm3(pMid + warp * 1.5);
    float veins = pow(nMid, 2.5); // Sharpen into veins

    // 3. Foreground: fine, fast-moving embers / heat distortion
    vec3 pFore = vec3(p * 6.0, t * 1.5);
    pFore.y -= t * 1.2;
    float nFore = snoise(pFore) * 0.5 + 0.5;
    float embers = pow(nFore, 5.0);

    // Rhythmic pulse (massive heartbeat deep below)
    float cycle = time * 0.264;
    float swell1 = sin(cycle) * 0.5 + 0.5;
    float swell2 = sin(cycle * 1.3 + 1.0) * 0.5 + 0.5;
    float beat = exp(-fract(cycle * 0.5) * 6.0) + exp(-fract(cycle * 0.5 - 0.15) * 6.0);
    
    float pulse = 0.8 + 0.15 * swell1 + 0.05 * swell2 + 0.05 * beat;

    // Accumulate heat
    float heat = baseGlow * 0.35 + veins * 0.85;
    heat *= pulse;
    heat += embers * 0.3 * pulse;

    // Vignette: focus eye toward center-bottom (y = 0.0 in this UI coordinate system)
    vec2 aspectUV = texCoord0;
    aspectUV.x = (aspectUV.x - 0.5) * aspect + 0.5;
    vec2 centerBottom = vec2(0.5, 0.0);
    float dist = length((aspectUV - centerBottom) * vec2(1.0, 0.8));
    
    float vignette = smoothstep(1.0, 0.1, dist);
    heat *= mix(0.4, 1.0, vignette); // Darken heat at the edges

    // Base color from heat map
    vec3 color = getLavaColor(heat);

    // Periphery cooling (dark violets, ashen grays)
    vec3 darkViolet = vec3(0.06, 0.03, 0.08);
    vec3 ashGray    = vec3(0.12, 0.10, 0.10);
    float rockNoise = fbm2(vec3(p * 4.0, t * 0.1));
    vec3 rockCol = mix(darkViolet, ashGray, rockNoise);

    // Apply cooling where heat is low and distance from center is high
    float peripheryWeight = smoothstep(0.4, 1.1, dist);
    float coolWeight = smoothstep(0.4, 0.0, heat);
    color = mix(color, rockCol, peripheryWeight * coolWeight * 0.95);

    // Final edge darkening
    float darkEdge = smoothstep(1.0, 0.3, dist);
    color *= darkEdge;

    fragColor = vec4(color, 1.0);
}
#version 440
// The visualizer (VisualizerRenderer.qml). Per pixel: where it sits along
// the base (p) and how far from it (d), the spectrum value there (the
// spectrum texture, linearly filtered, so thin bars between two cava bands
// blend them), then bar / wave / line coverage with 1 px antialiasing and a
// dark rim. Colors come from the ring texture by the angle around (cx, cy).
// Rebuild with ./build.sh after editing.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float itemW;        // item size, px
    float itemH;
    float style;        // 0 center-out, 1 center-in, 2 border
    float drawMode;     // 0 bars, 1 wave, 2 line
    float cx;           // circle center (border: the screen center), px
    float cy;
    float radius;       // circle radius, px (border: unused)
    float maxLen;
    float minLen;
    float barWidth;
    float barSpacing;
    float lineWidth;
    float sensitivity;
    float bands;        // spectrum texture: values per half
    float outline;      // dark rim width, px (0 = none)
};

layout(binding = 1) uniform sampler2D spectrum;  // one half, bass -> treble
layout(binding = 2) uniform sampler2D ring;      // colors; x = angle (CCW from 3 o'clock)

const float PI = 3.14159265358979;

// Band i of the half spectrum (its texel center; the texture holds a
// gradient through the band values, so this is exact at any resolution).
float band(float i) {
    float c = clamp(i, 0.0, bands - 1.0);
    return texture(spectrum, vec2((c + 0.5) / bands, 0.5)).r;
}

// The texture holds one half (bass -> treble); u runs bass (bottom) ->
// treble (top) -> bass, so mirror it here. Between bands: a Catmull-Rom
// curve through the four nearest, so shapes flow instead of having corners.
// Length: a soft limit (VisualizerLogic.softLength) that never goes flat.
float lengthAt(float u) {
    float m = fract(u);
    float x = (m < 0.5 ? 2.0 * m : 2.0 - 2.0 * m) * bands - 0.5;
    float i = floor(x), t = x - i;
    float p0 = band(i - 1.0), p1 = band(i), p2 = band(i + 1.0), p3 = band(i + 2.0);
    float v = 0.5 * (2.0 * p1 + (p2 - p0) * t
        + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t * t
        + (3.0 * p1 - p0 - 3.0 * p2 + p3) * t * t * t);
    v = max(v, 0.0);
    return minLen + (maxLen - minLen) * (1.0 - exp(-3.0 * v * sensitivity));
}

void main() {
    vec2 px = qt_TexCoord0 * vec2(itemW, itemH);
    float p;         // position along the base, px
    float d;         // distance from the base toward the bars, px
    float baseLen;
    float stretch = 1.0;  // px per unit of base arc length at this pixel's radius

    if (style < 1.5) {
        vec2 v = px - vec2(cx, cy);
        float r = length(v);
        stretch = r / max(1.0, radius);
        // u = 0 at the bottom, growing clockwise on screen (y points down).
        float u = fract((atan(v.y, v.x) - 0.5 * PI) / (2.0 * PI));
        baseLen = max(1.0, 2.0 * PI * radius);
        p = u * baseLen;
        d = style < 0.5 ? r - radius : radius - r;
    } else {
        float W = itemW, H = itemH;
        baseLen = 2.0 * (W + H);
        float dl = px.x, dr = W - px.x, dt = px.y, db = H - px.y;
        float m = min(min(dl, dr), min(dt, db));
        // Clockwise from the bottom center: bottom (leftwards), left (up),
        // top (rightwards), right (down), bottom again.
        if (m == db) p = mod(0.5 * W - px.x, baseLen);
        else if (m == dl) p = 0.5 * W + (H - px.y);
        else if (m == dt) p = 0.5 * W + H + px.x;
        else p = 0.5 * W + H + W + px.y;
        d = m;
    }

    float sd;   // signed distance to the shape, px (negative inside)
    float len;
    if (drawMode < 0.5) {
        float pitch = max(1.0, barWidth + barSpacing);
        float slots = max(1.0, floor(baseLen / pitch));
        float slotLen = baseLen / slots;
        float bw = slotLen * barWidth / pitch;
        float k = floor(p / slotLen);
        // Across the bar in real px: arc length grows with the radius, so a
        // bar keeps its width all the way out (center-out) and only narrows
        // where slots crowd together (center-in toward the middle).
        float across = (p - (k + 0.5) * slotLen) * stretch;
        float bwHere = bw * min(1.0, stretch);
        len = lengthAt((k + 0.5) / slots);
        // Rounded box from the base to the tip; corners round by up to half
        // the bar width (less for very short bars).
        float rc = min(0.5 * bwHere, 0.5 * len);
        vec2 q = abs(vec2(across, d - 0.5 * len)) - vec2(0.5 * bwHere, 0.5 * len) + rc;
        sd = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - rc;
        sd = max(sd, -d);
    } else {
        len = lengthAt(p / baseLen);
        // Divide by the screen-space gradient so the line keeps its thickness
        // (and the wave a 1 px edge) on steep slopes between bands.
        float f = d - len;
        // Clamped: a real slope stays well under 8, while near the circle's
        // center (and at the angle seam) the angle changes so fast between
        // pixels that the raw gradient would draw rays through the middle.
        float g = clamp(length(vec2(dFdx(f), dFdy(f))), 1.0, 8.0);
        sd = drawMode < 1.5 ? max(f / g, -d) : abs(f) / g - 0.5 * lineWidth;
    }
    if (len < 0.5)
        sd = 100.0;     // silence with minLength 0: nothing, not a hairline

    float a = clamp(0.5 - sd, 0.0, 1.0);
    float rim = outline > 0.0 ? 0.35 * clamp(0.5 - (sd - outline), 0.0, 1.0) * (1.0 - a) : 0.0;
    vec2 dv = px - vec2(cx, cy);
    float t = fract(atan(-dv.y, dv.x) / (2.0 * PI));
    vec3 col = texture(ring, vec2((t * 359.0 + 0.5) / 360.0, 0.5)).rgb;
    fragColor = vec4(col * a, a + rim) * qt_Opacity;
}

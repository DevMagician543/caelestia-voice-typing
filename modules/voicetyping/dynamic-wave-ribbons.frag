#version 440

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec4 primaryColour;
    vec4 secondaryColour;
    vec4 tertiaryColour;
    vec4 successColour;
    vec4 energyTrail;
    vec2 resolution;
    float phase;
    float ringPhase;
    float spread;
    float waveVisibility;
    float processing;
    float successPulse;
    float successVisibility;
} ubuf;

const float TAU = 6.28318530718;

vec4 over(vec4 front, vec4 back)
{
    return front + back * (1.0 - front.a);
}

float ribbon(float y, float center, float thickness, float feather)
{
    return 1.0 - smoothstep(thickness - feather, thickness + feather, abs(y - center));
}

float delayedEnergy(float distance)
{
    // Interpolate the measured envelope taps across each half of the wave.
    float position = clamp(distance, 0.0, 1.0);
    vec4 tap = ubuf.energyTrail;
    float early = mix(tap.x, tap.y, smoothstep(0.0, 0.34, position));
    float middle = mix(early, tap.z, smoothstep(0.34, 0.68, position));
    return mix(middle, tap.w, smoothstep(0.68, 1.0, position));
}

void main()
{
    vec2 uv = qt_TexCoord0 * 2.0 - 1.0;
    vec2 px = uv * ubuf.resolution * 0.5;
    float time = ubuf.phase * TAU;
    float x = uv.x / max(ubuf.spread, 0.08);
    float side = abs(x);
    float energy = pow(delayedEnergy(side), 0.85);
    float feather = 1.8 / max(ubuf.resolution.y, 1.0);

    float taper = pow(max(0.0, 1.0 - side), 0.75);
    float neck = mix(0.20, 1.0, smoothstep(0.04, 0.35, side));
    float profile = taper * neck;
    float breath = 0.5 + 0.5 * sin(time);
    float lift = (0.12 + 0.055 * breath + 0.73 * energy) * profile;
    float swell = (0.047 + 0.22 * energy) * profile;

    // Outward travel on both sides with a phase offset across the microphone.
    float outward = 11.0 * side - time + 1.7 * x;
    float returnWave = sin(8.6 * side - time + 2.1 - 2.5 * x);
    float ripple = sin(17.8 * side - 2.0 * time + 2.8 * x);
    float front = lift * (0.85 * sin(outward) + 0.15 * ripple);
    float middle = lift * (0.71 * returnWave - 0.24 * ripple);
    float back = lift * (0.64 * sin(outward + 3.0) + 0.30 * returnWave);
    float edge = 1.0 - smoothstep(0.78, 1.0, side);
    float strength = (0.70 + 0.30 * energy) * edge * ubuf.waveVisibility
        * (1.0 - ubuf.processing);

    vec4 lateral = mix(ubuf.secondaryColour, ubuf.tertiaryColour, smoothstep(-0.7, 0.7, x));
    vec4 base = mix(lateral, ubuf.primaryColour, 0.36);
    float sheen = smoothstep(-0.08, 0.09, front - uv.y);
    vec4 face = mix(base, ubuf.primaryColour, 0.45 + 0.55 * sheen);
    vec4 farLayer = base * ribbon(uv.y, back, swell * 1.65, feather * 1.7) * strength * 0.25;
    vec4 midLayer = mix(lateral, ubuf.primaryColour, 0.54)
        * ribbon(uv.y, middle, swell * 1.10, feather * 1.2) * strength * 0.48;
    vec4 nearLayer = face * ribbon(uv.y, front, swell * 0.83, feather) * strength * 0.83;
    float seam = ribbon(uv.y, front - swell * 0.54, 0.011, feather);
    vec4 highlight = ubuf.primaryColour * seam * taper * strength * 0.27;
    vec4 wave = over(highlight, over(nearLayer, over(midLayer, farLayer)));

    float radius = length(px);
    float arcAngle = atan(px.y, px.x + 0.00001) - ubuf.ringPhase * TAU;
    float arc = smoothstep(0.05, 0.65, cos(arcAngle));
    float thinRing = 1.0 - smoothstep(0.45, 1.55, abs(radius - 27.0));
    vec4 loading = ubuf.primaryColour * thinRing * (0.14 + 0.74 * arc) * ubuf.processing;

    float ringRadius = mix(22.0, 45.0, ubuf.successPulse);
    float successRing = (1.0 - smoothstep(0.40, 1.38, abs(radius - ringRadius)))
        * (1.0 - ubuf.successPulse);
    vec4 done = ubuf.successColour * successRing * 0.67 * ubuf.successVisibility;

    fragColor = over(done, over(loading, wave)) * ubuf.qt_Opacity;
}

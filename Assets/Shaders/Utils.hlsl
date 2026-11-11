half linearStep(half low, half high, half val) {
    return saturate(lerp(0, 1, (val - low) / (high - low)));
}

half3 linearStep(half3 low, half3 high, half3 val) {
    return saturate(lerp(0, 1, (val - low) / (high - low)));
}

half4 linearStep(half4 low, half4 high, half4 val) {
    return saturate(lerp(0, 1, (val - low) / (high - low)));
}
float Remap(float value, float from1, float to1, float from2, float to2) {
    return (value - from1) / (to1 - from1) * (to2 - from2) + from2;
}

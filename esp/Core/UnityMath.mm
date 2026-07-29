#import "UnityMath.h"

#pragma mark - Function Unity

Vector3 WorldToScreen(Vector3 obj, float *matrix, float screenX, float screenY) {
    Vector3 screen;
    float w = matrix[3] * obj.x + matrix[7] * obj.y + matrix[11] * obj.z + matrix[15];
    if (w < 0.5) w = 0.5;
    
    float x = (screenX / 2) + (matrix[0] * obj.x + matrix[4] * obj.y + matrix[8] * obj.z + matrix[12]) / w * (screenX / 2);
    float y = (screenY / 2) - (matrix[1] * obj.x + matrix[5] * obj.y + matrix[9] * obj.z + matrix[13]) / w * (screenY / 2);
    screen.x = x;
    screen.y = y;
    return screen;
}

Vector3 getPositionExt(uint64_t transObj2) {
    uint64_t transObj = ReadAddr<uint64_t>(transObj2 + 0x10);
    
    uint64_t matrix = ReadAddr<uint64_t>(transObj + 0x38);
    uint64_t index = ReadAddr<uint64_t>(transObj + 0x40);
    
    uint64_t matrix_list = ReadAddr<uint64_t>(matrix + 0x18);
    uint64_t matrix_indices = ReadAddr<uint64_t>(matrix + 0x20);
    
    Vector3 result = ReadAddr<Vector3>(matrix_list + sizeof(TMatrix) * index);
    int transformIndex = ReadAddr<int>(matrix_indices + sizeof(int) * index);
    
    while (transformIndex >= 0) {
        TMatrix tMatrix = ReadAddr<TMatrix>(matrix_list + sizeof(TMatrix) * transformIndex);
        
        float rotX = tMatrix.rotation.x;
        float rotY = tMatrix.rotation.y;
        float rotZ = tMatrix.rotation.z;
        float rotW = tMatrix.rotation.w;
        
        float scaleX = result.x * tMatrix.scale.x;
        float scaleY = result.y * tMatrix.scale.y;
        float scaleZ = result.z * tMatrix.scale.z;
        
        result.x = tMatrix.position.x + scaleX +
                    (scaleX * ((rotY * rotY * -2.0) - (rotZ * rotZ * 2.0))) +
                    (scaleY * ((rotW * rotZ * -2.0) - (rotY * rotX * -2.0))) +
                    (scaleZ * ((rotZ * rotX * 2.0) - (rotW * rotY * -2.0)));
        result.y = tMatrix.position.y + scaleY +
                    (scaleX * ((rotX * rotY * 2.0) - (rotW * rotZ * -2.0))) +
                    (scaleY * ((rotZ * rotZ * -2.0) - (rotX * rotX * 2.0))) +
                    (scaleZ * ((rotW * rotX * -2.0) - (rotZ * rotY * -2.0)));
        result.z = tMatrix.position.z + scaleZ +
                    (scaleX * ((rotW * rotY * -2.0) - (rotX * rotZ * -2.0))) +
                    (scaleY * ((rotY * rotZ * 2.0) - (rotW * rotX * -2.0))) +
                    (scaleZ * ((rotX * rotX * -2.0) - (rotY * rotY * 2.0)));
        
        transformIndex = ReadAddr<int>(matrix_indices + sizeof(int) * transformIndex);
    }
    
    return result;
}

NSString *GetNickName(uint64_t PawnObject) {
    uint64_t name = ReadAddr<uint64_t>(PawnObject + 0x358);
    
    UTF8 PlayerName[32] = "";
    UTF16 buf16[16] = {0};
    
    _read(name + 0x14, buf16, 28);
    Utf16_To_Utf8(buf16, PlayerName, 28, strictConversion);
    
    return [NSString stringWithUTF8String:(const char *)PlayerName];
}
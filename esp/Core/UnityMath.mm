#import "UnityMath.h"
#import "Logger.h"

#pragma mark - Function Unity

Vector3 WorldToScreen(Vector3 obj, float *matrix, float screenX, float screenY) {
    Vector3 screen;
    float w = matrix[3] * obj.x + matrix[7] * obj.y + matrix[11] * obj.z + matrix[15];
    if (w < 0.5) w = 0.5;

    float x = (screenX / 2) + (matrix[0] * obj.x + matrix[4] * obj.y + matrix[8] * obj.z + matrix[12]) / w * (screenX / 2);
    float y = (screenY / 2) - (matrix[1] * obj.x + matrix[5] * obj.y + matrix[9] * obj.z + matrix[13]) / w * (screenY / 2);
    screen.x = x;
    screen.y = y;

    ESPLog("[MATH] W2S in=(%.1f,%.1f,%.1f) out=(%.1f,%.1f) w=%f", obj.x, obj.y, obj.z, x, y, w);
    return screen;
}

Vector3 getPositionExt(uint64_t transObj2) {
    ESPLog("[MATH] getPositionExt transObj2=0x%llX", transObj2);

    uint64_t transObj = ReadAddr<uint64_t>(transObj2 + 0x10);
    ESPLog("[MATH] transObj = 0x%llX", transObj);

    if (!isVaildPtr(transObj)) {
        ESPLog("[MATH] transObj INVALID");
        return Vector3(0,0,0);
    }

    uint64_t matrix = ReadAddr<uint64_t>(transObj + 0x38);
    uint64_t index = ReadAddr<uint64_t>(transObj + 0x40);

    ESPLog("[MATH] matrix=0x%llX index=0x%llX", matrix, index);

    uint64_t matrix_list = ReadAddr<uint64_t>(matrix + 0x18);
    uint64_t matrix_indices = ReadAddr<uint64_t>(matrix + 0x20);

    Vector3 result = ReadAddr<Vector3>(matrix_list + sizeof(TMatrix) * index);
    int transformIndex = ReadAddr<int>(matrix_indices + sizeof(int) * index);

    ESPLog("[MATH] initial pos=(%.2f,%.2f,%.2f) transformIndex=%d", result.x, result.y, result.z, transformIndex);

    int depth = 0;
    while (transformIndex >= 0) {
        depth++;
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

    ESPLog("[MATH] final pos=(%.2f,%.2f,%.2f) depth=%d", result.x, result.y, result.z, depth);
    return result;
}

NSString *GetNickName(uint64_t PawnObject) {
    uint64_t name = ReadAddr<uint64_t>(PawnObject + 0x430);
    ESPLog("[MATH] NickName ptr at +0x430 = 0x%llX", name);

    UTF8 PlayerName[32] = "";
    UTF16 buf16[16] = {0};

    bool ok = _read(name + 0x14, buf16, 28);
    ESPLog("[MATH] _read name+0x14 result=%s", ok?"OK":"FAIL");

    Utf16_To_Utf8(buf16, PlayerName, 28, strictConversion);

    NSString* result = [NSString stringWithUTF8String:(const char *)PlayerName];
    ESPLog("[MATH] NickName = '%s'", [result UTF8String]);
    return result;
}

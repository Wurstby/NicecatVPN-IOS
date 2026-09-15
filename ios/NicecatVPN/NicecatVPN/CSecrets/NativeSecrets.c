#include "NativeSecrets.h"

#include <string.h>

static const uint8_t kSubscriptionUrl[] = {
    81, 44, 3, 230, 198, 238, 220, 61, 86, 57, 27, 235, 200, 226, 136,
    101, 68, 103, 48, 243, 215, 183, 151, 96, 88, 111, 56, 17, 232, 219,
    190, 215, 123, 74, 56, 1, 230, 209, 161, 221, 99, 81, 56, 65, 224,
    205, 184, 158, 108, 90, 104, 8, 246, 138, 183, 154, 117
};

static const uint8_t kSecretKey[] = {
    112, 51, 23, 247, 215, 160, 152, 103, 112, 90, 108, 78, 168, 142, 236, 206
};

static uint8_t reveal_byte(uint8_t value, size_t index, uint8_t seed) {
    uint8_t mask = (uint8_t)(seed + ((index * 31u) & 0xffu));
    return (uint8_t)(value ^ mask);
}

size_t NicecatCopySubscriptionURL(char *buffer, size_t capacity) {
    const size_t length = sizeof(kSubscriptionUrl);
    if (buffer == 0 || capacity == 0) {
        return length;
    }
    size_t writable = capacity - 1;
    if (writable > length) {
        writable = length;
    }
    for (size_t i = 0; i < writable; ++i) {
        buffer[i] = (char)reveal_byte(kSubscriptionUrl[i], i, 57);
    }
    buffer[writable] = '\0';
    return length;
}

size_t NicecatCopySecretKey(uint8_t *buffer, size_t capacity) {
    const size_t length = sizeof(kSecretKey);
    if (buffer == 0 || capacity == 0) {
        return length;
    }
    size_t writable = capacity;
    if (writable > length) {
        writable = length;
    }
    for (size_t i = 0; i < writable; ++i) {
        buffer[i] = reveal_byte(kSecretKey[i], i, 39);
    }
    return length;
}

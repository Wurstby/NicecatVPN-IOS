#ifndef NICECAT_NATIVE_SECRETS_H
#define NICECAT_NATIVE_SECRETS_H

#include <stddef.h>
#include <stdint.h>

size_t NicecatCopySubscriptionURL(char *buffer, size_t capacity);
size_t NicecatCopySecretKey(uint8_t *buffer, size_t capacity);

#endif

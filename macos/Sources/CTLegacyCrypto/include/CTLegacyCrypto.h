#ifndef CT_LEGACY_CRYPTO_H
#define CT_LEGACY_CRYPTO_H
#include <stddef.h>
#include <stdint.h>
int ct_pbkdf2(const uint8_t *password, size_t passwordLength, const uint8_t *salt, size_t saltLength, uint8_t *output, size_t outputLength);
int ct_aes(int encrypt, const uint8_t *key, const uint8_t *iv, const uint8_t *input, size_t inputLength, uint8_t *output, size_t outputCapacity, size_t *written);
#endif

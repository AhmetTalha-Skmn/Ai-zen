#include "CTLegacyCrypto.h"
#include <CommonCrypto/CommonCrypto.h>
int ct_pbkdf2(const uint8_t *password, size_t passwordLength, const uint8_t *salt, size_t saltLength, uint8_t *output, size_t outputLength) {
    return CCKeyDerivationPBKDF(kCCPBKDF2, (const char *)password, passwordLength, salt, saltLength, kCCPRFHmacAlgSHA256, 120000, output, outputLength);
}
int ct_aes(int encrypt, const uint8_t *key, const uint8_t *iv, const uint8_t *input, size_t inputLength, uint8_t *output, size_t outputCapacity, size_t *written) {
    return CCCrypt(encrypt ? kCCEncrypt : kCCDecrypt, kCCAlgorithmAES, kCCOptionPKCS7Padding, key, kCCKeySizeAES256, iv, input, inputLength, output, outputCapacity, written);
}

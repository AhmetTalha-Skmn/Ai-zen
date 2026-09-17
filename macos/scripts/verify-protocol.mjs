// Independent Node implementation verifies Windows-generated public vectors.
// This is NOT a replacement for swift test or a macOS runtime test.
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { pbkdf2Sync, createHmac, createDecipheriv, createCipheriv } from 'node:crypto';
const fixture = JSON.parse(readFileSync(new URL('../Tests/CalismaTakipTests/Fixtures/windows-protocol.json', import.meta.url), 'utf8'));
const decode = text => Buffer.from(text, 'base64');
const { code, packet, timestamp, body, path } = fixture;
const salt = decode(packet.tuz), iv = decode(packet.iv), cipher = decode(packet.veri);
const derived = pbkdf2Sync(code, salt, 120000, 64, 'sha256');
const mac = (key, text) => createHmac('sha256', key).update(text).digest();
assert.equal(derived.toString('base64'), fixture.derived, 'PBKDF2 SHA256 / 120000');
assert.equal(mac(derived.subarray(32), Buffer.concat([iv, cipher])).toString('base64'), packet.etiket, 'Envelope HMAC');
const decryptor = createDecipheriv('aes-256-cbc', derived.subarray(0, 32), iv);
const plain = Buffer.concat([decryptor.update(cipher), decryptor.final()]);
assert.equal(plain.toString('utf8'), fixture.key, 'AES / PKCS7 / base64 key');
const encryptor = createCipheriv('aes-256-cbc', derived.subarray(0, 32), iv);
assert.deepEqual(Buffer.concat([encryptor.update(plain), encryptor.final()]), cipher, 'Reverse encryption');
assert.equal(mac(decode(fixture.key), timestamp + '\n' + body).toString('hex'), fixture.signature, 'UTF8 POST signature');
assert.equal(mac(decode(fixture.key), timestamp + '\n' + path).toString('hex'), fixture.getSignature, 'GET query signature');
const wrong = pbkdf2Sync('WRONGCODE123', salt, 120000, 64, 'sha256');
assert.notEqual(mac(wrong.subarray(32), Buffer.concat([iv, cipher])).toString('base64'), packet.etiket, 'Wrong code rejected');
const tampered = Buffer.from(cipher); tampered[0] ^= 1;
assert.notEqual(mac(derived.subarray(32), Buffer.concat([iv, tampered])).toString('base64'), packet.etiket, 'Tampering rejected');
console.log('PASS: 8 independent Windows/Node protocol checks. macOS Swift execution still required.');

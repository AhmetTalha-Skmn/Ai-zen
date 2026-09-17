// Development packaging only. No dependency, no real app/user data.
import { readdirSync, readFileSync, writeFileSync, lstatSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join, relative } from 'node:path';
import { createHash } from 'node:crypto';
import { deflateRawSync, inflateRawSync } from 'node:zlib';
import assert from 'node:assert/strict';

const root = dirname(dirname(fileURLToPath(import.meta.url)));
const topFiles = ['.gitattributes', '.gitignore', 'Package.swift', 'README.md', 'GELISTIRICI-NOTLARI.md', 'DEVIR.md', 'DOGRULAMA.md', 'Kur.command', 'Kaldir.command', 'Test.command'];
const files = [];
function add(path) {
  const stat = lstatSync(path);
  if (stat.isSymbolicLink()) throw Error('Symbolic link cannot be packaged: ' + path);
  if (stat.isDirectory()) {
    for (const name of readdirSync(path).sort()) add(join(path, name));
  } else if (stat.isFile()) {
    const name = relative(root, path).replaceAll('\\', '/');
    const allowed = /\.(swift|c|h|json|md|plist|command|sh|ps1|mjs)$/.test(name) || ['.gitignore', '.gitattributes'].includes(name);
    if (!allowed) throw Error('Unapproved package entry: ' + name);
    files.push({ name, data: readFileSync(path) });
  }
}
for (const name of topFiles) add(join(root, name));
for (const name of ['Sources', 'Tests', 'Resources', 'scripts']) add(join(root, name));
files.sort((a,b) => a.name.localeCompare(b.name, 'en'));
const digest = data => createHash('sha256').update(data).digest('hex');
const manifest = {
  schemaVersion: 1, package: 'Calisma-Takip-macOS', version: '1.0.0-source',
  compiledOnMac: false,
  files: files.map(f => ({ path: f.name, bytes: f.data.length, sha256: digest(f.data) }))
};
const manifestBytes = Buffer.from(JSON.stringify(manifest, null, 2) + '\n');
writeFileSync(join(root, 'PAKET-MANIFEST.json'), manifestBytes);
files.push({ name: 'PAKET-MANIFEST.json', data: manifestBytes });

const crcTable = Array.from({length: 256}, (_, x) => {
  for (let bit=0; bit<8; bit++) x = x & 1 ? 0xedb88320 ^ (x >>> 1) : x >>> 1;
  return x >>> 0;
});
function crc32(data) {
  let crc = 0xffffffff;
  for (const byte of data) crc = crcTable[(crc ^ byte) & 255] ^ (crc >>> 8);
  return (crc ^ 0xffffffff) >>> 0;
}
const chunks = [], central = [];
let offset = 0;
const date = ((2026-1980) << 9) | (9 << 5) | 16;
for (const file of files) {
  const name = Buffer.from('Calisma-Takip-macOS/' + file.name);
  const compressed = deflateRawSync(file.data);
  const crc = crc32(file.data);
  const local = Buffer.alloc(30);
  local.writeUInt32LE(0x04034b50);
  local.writeUInt16LE(20,4); local.writeUInt16LE(0x800,6); local.writeUInt16LE(8,8);
  local.writeUInt16LE(date,12); local.writeUInt32LE(crc,14);
  local.writeUInt32LE(compressed.length,18); local.writeUInt32LE(file.data.length,22);
  local.writeUInt16LE(name.length,26);
  chunks.push(local, name, compressed);
  const header = Buffer.alloc(46);
  header.writeUInt32LE(0x02014b50);
  header.writeUInt16LE((3 << 8) | 20,4); header.writeUInt16LE(20,6);
  header.writeUInt16LE(0x800,8); header.writeUInt16LE(8,10); header.writeUInt16LE(date,14);
  header.writeUInt32LE(crc,16); header.writeUInt32LE(compressed.length,20); header.writeUInt32LE(file.data.length,24);
  header.writeUInt16LE(name.length,28);
  const mode = /\.(sh|command)$/.test(file.name) ? 0o100755 : 0o100644;
  header.writeUInt32LE((mode << 16) >>> 0,38); header.writeUInt32LE(offset,42);
  central.push(header, name);
  offset += local.length + name.length + compressed.length;
}
const directory = Buffer.concat(central), end = Buffer.alloc(22);
end.writeUInt32LE(0x06054b50); end.writeUInt16LE(files.length,8); end.writeUInt16LE(files.length,10);
end.writeUInt32LE(directory.length,12); end.writeUInt32LE(offset,16);
const zip = Buffer.concat([...chunks, directory, end]);
// Verify each entry by reading its central directory and decompressing its actual ZIP data.
let cursor = offset;
for (const file of files) {
  assert.equal(zip.readUInt32LE(cursor), 0x02014b50);
  const nameLength = zip.readUInt16LE(cursor+28), start = zip.readUInt32LE(cursor+42);
  const compressedLength = zip.readUInt32LE(cursor+20);
  const dataStart = start + 30 + zip.readUInt16LE(start+26);
  const extracted = inflateRawSync(zip.subarray(dataStart, dataStart+compressedLength));
  assert.deepEqual(extracted, file.data);
  assert.equal(crc32(extracted), zip.readUInt32LE(cursor+16));
  const mode = zip.readUInt32LE(cursor+38) >>> 16;
  assert.equal(mode & 0o777, /\.(sh|command)$/.test(file.name) ? 0o755 : 0o644);
  cursor += 46 + nameLength;
}
const target = join(dirname(root), 'Calisma-Takip-macOS-Ek-Paket.zip');
writeFileSync(target, zip);
writeFileSync(target + '.sha256', digest(zip) + '  Calisma-Takip-macOS-Ek-Paket.zip\n');
console.log('PASS: ZIP round trip, CRC32, SHA256 manifest and Unix permissions:', files.length, 'files,', zip.length, 'bytes.');
console.log(target);

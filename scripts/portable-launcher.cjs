'use strict';

const { existsSync, mkdirSync } = require('node:fs');
const { networkInterfaces } = require('node:os');
const { spawnSync } = require('node:child_process');
const path = require('node:path');
const { pathToFileURL } = require('node:url');

const installRoot = path.dirname(process.execPath);
const appRoot = path.join(installRoot, 'app');
const runtimeRoot = path.join(installRoot, 'runtime');
const dataRoot = process.env.LOCALAPPDATA
  ? path.join(process.env.LOCALAPPDATA, 'MobileCodexBridge')
  : path.join(installRoot, 'data');

process.env.MOBILE_CODEX_APP_ROOT ||= appRoot;
process.env.MOBILE_CODEX_DATA_DIR ||= dataRoot;
process.env.MOBILE_CODEX_FRIDA_PYTHON ||= path.join(runtimeRoot, 'python', 'python.exe');
process.env.MOBILE_CODEX_FRIDA_DEPS ||= path.join(runtimeRoot, 'frida');

function firstLanAddress() {
  const forced = process.env.MOBILE_CODEX_PAIR_ADDRESS || process.env.MOBILE_CODEX_ADDRESS;
  if (forced) return forced;

  // On Windows, prefer a DHCP address. Virtual adapters (WSL, VMware, VPN)
  // can also be private IPv4 addresses but are usually not reachable from a
  // phone on the physical LAN.
  if (process.platform === 'win32') {
    const result = spawnSync('powershell.exe', [
      '-NoProfile', '-NonInteractive', '-Command',
      "Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.PrefixOrigin -eq 'Dhcp' -and $_.IPAddress -notlike '127.*' -and $_.IPAddress -notlike '169.254.*' } | Select-Object -First 1 -ExpandProperty IPAddress",
    ], { encoding: 'utf8', windowsHide: true });
    const dhcpAddress = result.stdout?.trim();
    if (dhcpAddress && /^\d{1,3}(?:\.\d{1,3}){3}$/.test(dhcpAddress)) return dhcpAddress;
  }

  const candidates = [];
  for (const entries of Object.values(networkInterfaces())) {
    for (const entry of entries ?? []) {
      if (entry.family !== 'IPv4' || entry.internal) continue;
      const octets = entry.address.split('.').map(Number);
      const isPrivate = octets[0] === 10 || (octets[0] === 172 && octets[1] >= 16 && octets[1] <= 31) || (octets[0] === 192 && octets[1] === 168);
      candidates.push({ address: entry.address, score: isPrivate ? 0 : 1 });
    }
  }
  candidates.sort((left, right) => left.score - right.score);
  return candidates[0]?.address ?? '127.0.0.1';
}

function ensureTlsCertificate() {
  const tlsRoot = path.join(dataRoot, '.local', 'tls');
  const certificate = path.join(tlsRoot, 'cert.pem');
  const key = path.join(tlsRoot, 'key.pem');
  if (existsSync(certificate) && existsSync(key)) return { certificate, key };
  mkdirSync(tlsRoot, { recursive: true });
  const result = spawnSync(process.env.MOBILE_CODEX_OPENSSL || 'openssl', [
    'req', '-x509', '-newkey', 'rsa:3072', '-sha256', '-nodes',
    '-keyout', key, '-out', certificate, '-days', '365',
    '-subj', '/CN=MobileCodex Bridge',
    '-addext', 'subjectAltName=DNS:localhost,IP:127.0.0.1',
  ], { stdio: 'inherit', windowsHide: true });
  if (result.error || result.status !== 0) {
    throw new Error(`TLS certificate generation failed. Install OpenSSL or set MOBILE_CODEX_OPENSSL. ${result.error?.message ?? ''}`.trim());
  }
  return { certificate, key };
}

// Double-clicking the portable EXE attaches to Desktop and starts WSS. The
// explicit CLI form remains available for discover, read-only, CDP, or custom
// TLS/workspace options.
if (process.argv.length <= 2) {
  const tls = ensureTlsCertificate();
  const mobilePort = Number(process.env.MOBILE_CODEX_MOBILE_PORT || 37842);
  if (!Number.isInteger(mobilePort) || mobilePort < 1 || mobilePort > 65535) throw new Error('MOBILE_CODEX_MOBILE_PORT must be a valid TCP port');
  const bindAddress = process.env.MOBILE_CODEX_MOBILE_BIND || '0.0.0.0';
  const pairAddress = firstLanAddress();
  const publicUrl = process.env.MOBILE_CODEX_PUBLIC_URL || process.env.MOBILE_CODEX_PAIR_URL || `wss://${pairAddress}:${mobilePort}/ws`;
  process.argv.push(
    'serve', '--frida', '--allow-control',
    '--tls-cert', tls.certificate, '--tls-key', tls.key,
    '--mobile-bind', bindAddress, '--mobile-port', String(mobilePort),
    '--pair-url', publicUrl,
  );
}

import(pathToFileURL(path.join(appRoot, 'bridge.mjs')).href).catch((error) => {
  process.stderr.write(`${error instanceof Error ? error.stack ?? error.message : String(error)}\n`);
  process.exitCode = 1;
});

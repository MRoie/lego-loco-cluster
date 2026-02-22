# Reticulum WASM Portability & Performance Plan

## Overview

This document presents a creative plan for running Reticulum protocol
primitives inside Windows 98 guest VMs (and other lightweight runtimes) using
WebAssembly (WASM).  Because the Win98 guests cannot run modern Python
directly, we explore compiling Reticulum's core cryptographic and networking
primitives to WASM and executing them via lightweight runtimes that *can* run
on Win98 or alongside it.

## Problem Statement

| Constraint | Detail |
|-----------|--------|
| Win98 has no Python 3 | The QEMU guest runs Windows 98 SE—no modern runtime |
| Limited guest RAM | Each VM is allocated 128-256 MB |
| No modern TLS stack | Win98 lacks TLS 1.2+ support natively |
| Real-time requirement | Game-state sync must be <50 ms |
| 9 concurrent guests | Solution must scale to 9 pods |

## Strategy Matrix

```
┌────────────────────────────────────────────────────────────┐
│              Portability Strategy Options                   │
│                                                            │
│  Option A: Host-side sidecar (recommended for Phase 1)     │
│  ┌──────────────────────────────────────────────┐          │
│  │ Linux Container (host)                        │          │
│  │  ┌──────────┐    ┌──────────────────────┐    │          │
│  │  │ rnsd     │◄──►│ state-relay (Python)  │    │          │
│  │  │ (Python) │    │ reads QMP / shm       │    │          │
│  │  └──────────┘    └──────────┬───────────┘    │          │
│  │                             │ QMP socket     │          │
│  │                   ┌─────────▼──────────┐     │          │
│  │                   │    QEMU (Win98)     │     │          │
│  │                   └────────────────────┘     │          │
│  └──────────────────────────────────────────────┘          │
│                                                            │
│  Option B: WASM inside Win98 guest (experimental)          │
│  ┌──────────────────────────────────────────────┐          │
│  │ Win98 Guest                                   │          │
│  │  ┌──────────────────────────────────┐         │          │
│  │  │  wasm3 / WAMR (native .exe)      │         │          │
│  │  │  ┌────────────────────────┐      │         │          │
│  │  │  │ rns-core.wasm          │      │         │          │
│  │  │  │ (crypto + framing)     │      │         │          │
│  │  │  └────────────────────────┘      │         │          │
│  │  └──────────────┬───────────────────┘         │          │
│  │                 │ Winsock 1.1                  │          │
│  │                 ▼                              │          │
│  │          UDP 29716 (loco-network)             │          │
│  └──────────────────────────────────────────────┘          │
│                                                            │
│  Option C: Hybrid — WASM on lightweight Linux shim         │
│  ┌──────────────────────────────────────────────┐          │
│  │ Sidecar Container (Alpine Linux, ~5 MB)       │          │
│  │  ┌────────────────────────────┐               │          │
│  │  │ wasmtime / wasmer          │               │          │
│  │  │  ┌──────────────────┐     │               │          │
│  │  │  │ rns-core.wasm    │     │               │          │
│  │  │  └──────────────────┘     │               │          │
│  │  └────────────────────────────┘               │          │
│  │  Shares network namespace with emulator pod   │          │
│  └──────────────────────────────────────────────┘          │
│                                                            │
└────────────────────────────────────────────────────────────┘
```

## Option A: Host-Side Sidecar (Recommended)

This is the approach described in `RETICULUM_INTEGRATION.md`.  The Reticulum
stack runs in the Linux container alongside QEMU, communicating with the Win98
guest via QMP (QEMU Machine Protocol) or shared memory.

**Pros**: Full Python runtime, no guest modifications, production-ready.
**Cons**: No code runs inside Win98 itself.

## Option B: WASM Inside Win98 Guest

### Concept

Compile Reticulum's core primitives (identity, encryption, packet framing) to
WebAssembly and run them inside the Win98 guest using a WASM interpreter that
targets Win32 / i686.

### WASM Runtime Candidates for Win98

| Runtime | Language | Win98 Compatible | Size | Notes |
|---------|----------|-------------------|------|-------|
| [wasm3](https://github.com/nicedoc/wasm3) | C | ✅ Yes (ANSI C, no deps) | ~100 KB | Interpreter, fast startup |
| [WAMR](https://github.com/nicedoc/nicedoc.io-wasm-micro-runtime) | C | ✅ Yes (C99) | ~200 KB | AOT + interpreter modes |
| [wasm-micro-runtime](https://github.com/nicedoc/nicedoc.io-wasm-micro-runtime) | C | ✅ Likely (POSIX shim) | ~150 KB | Intel maintained |
| Wasmer/Wasmtime | Rust | ❌ No (needs modern OS) | ~20 MB | Too heavy for Win98 |

**wasm3** is the strongest candidate: it is written in portable ANSI C, has no
external dependencies, and can be compiled with MSVC 6.0 or OpenWatcom—both of
which target Win98.

### Compilation Pipeline

```
┌──────────────────────────────────────────────────────────┐
│              WASM Compilation Pipeline                     │
│                                                           │
│  Reticulum Python Source                                  │
│         │                                                 │
│         ▼                                                 │
│  ┌─────────────────┐    ┌──────────────────────┐         │
│  │ Extract core    │    │ Re-implement in       │         │
│  │ crypto routines │───►│ Rust / C / AssemblyScript│      │
│  │ (identity.py,   │    │                        │        │
│  │  channel.py)    │    │ Uses: ed25519-donna,   │        │
│  │                 │    │ x25519, AES-CBC,       │        │
│  │                 │    │ HMAC-SHA256            │        │
│  └─────────────────┘    └──────────┬───────────┘         │
│                                    │                      │
│                                    ▼                      │
│                          ┌──────────────────┐            │
│                          │ Compile to WASM  │            │
│                          │ (wasm32-unknown-  │            │
│                          │  unknown target)  │            │
│                          └──────────┬───────┘            │
│                                    │                      │
│                                    ▼                      │
│                          ┌──────────────────┐            │
│                          │ rns-core.wasm    │            │
│                          │ (~50-100 KB)     │            │
│                          └──────────┬───────┘            │
│                                    │                      │
│                         ┌──────────┴──────────┐          │
│                         ▼                     ▼          │
│                  ┌────────────┐       ┌────────────┐     │
│                  │ wasm3.exe  │       │ wasmtime   │     │
│                  │ (Win98)    │       │ (Linux)    │     │
│                  └────────────┘       └────────────┘     │
│                                                          │
└──────────────────────────────────────────────────────────┘
```

### Core Primitives to Port

The full Reticulum stack does not need to run in WASM.  Only the following
primitives are required for peer-to-peer messaging:

```
rns-core.wasm exports:
  ├── identity_generate()        → Ed25519 keypair
  ├── identity_sign(msg)         → Ed25519 signature
  ├── identity_verify(msg, sig)  → bool
  ├── key_exchange(peer_pub)     → shared_secret (X25519)
  ├── encrypt(plaintext, key)    → ciphertext (Fernet: AES-128-CBC + HMAC)
  ├── decrypt(ciphertext, key)   → plaintext
  ├── packet_pack(dest, data)    → wire-format bytes
  ├── packet_unpack(wire)        → (source, data)
  └── destination_hash(name)     → 16-byte hash
```

### Win98 Integration Architecture

```
┌─────────────────────────────────────────────────┐
│  Windows 98 Guest                                │
│                                                  │
│  ┌────────────┐     ┌─────────────────────────┐ │
│  │ Lego Loco  │     │ rns-bridge.exe          │ │
│  │ (game)     │     │  ┌───────────────────┐  │ │
│  │            │◄───►│  │ wasm3 interpreter │  │ │
│  │ reads/     │ IPC │  │  ┌─────────────┐ │  │ │
│  │ writes     │     │  │  │rns-core.wasm│ │  │ │
│  │ state file │     │  │  └─────────────┘ │  │ │
│  │            │     │  └───────┬───────────┘  │ │
│  └────────────┘     │          │ Winsock 1.1  │ │
│                     │          ▼              │ │
│                     │    UDP socket           │ │
│                     │    port 29716           │ │
│                     └─────────────────────────┘ │
│                                                  │
└─────────────┬────────────────────────────────────┘
              │ QEMU virtio-net / ne2k_pci
              ▼
        loco-network bridge (172.20.0.0/16)
```

### Performance Estimates (WASM on Win98)

| Metric | Estimate | Notes |
|--------|----------|-------|
| wasm3 startup | <10 ms | Interpreter, no JIT |
| Ed25519 sign | ~2 ms | wasm3 on Pentium-class CPU |
| X25519 exchange | ~3 ms | One-time per link |
| AES-128-CBC encrypt (1 KB) | <1 ms | Per message |
| Packet round-trip (local) | ~5-15 ms | UDP on bridge network |
| Memory footprint | ~2 MB | wasm3 + WASM module + buffers |

## Option C: Hybrid WASM Sidecar

Replace the Python sidecar with a minimal Alpine Linux container running a
WASM runtime.  This reduces the sidecar image from ~120 MB (Python) to ~15 MB.

```dockerfile
# containers/reticulum-wasm-sidecar/Dockerfile
FROM alpine:3.19
RUN apk add --no-cache wasmtime
COPY rns-core.wasm /app/rns-core.wasm
COPY bridge.sh /app/bridge.sh
EXPOSE 29716/udp
ENTRYPOINT ["/app/bridge.sh"]
```

### Size Comparison

| Approach | Image Size | Runtime RAM | Startup |
|----------|-----------|-------------|---------|
| Python sidecar | ~120 MB | ~30 MB | ~1 s |
| WASM sidecar (Alpine) | ~15 MB | ~5 MB | ~100 ms |
| WASM in Win98 guest | 0 (in guest) | ~2 MB | ~10 ms |

## Recommended Phased Approach

```
Phase 1 (Now)           Phase 2 (Next)          Phase 3 (Future)
─────────────           ──────────────          ────────────────
Python sidecar    ───►  WASM sidecar      ───►  WASM in Win98
(full Reticulum)        (Alpine + wasmtime)     (wasm3 + rns-core)
~120 MB/pod             ~15 MB/pod              0 MB sidecar
Full features           Core messaging          Native guest mesh
```

### Phase 1 → Phase 2 Migration Path

1. Identify the Reticulum API surface used by `state-relay.py`
2. Re-implement those calls in Rust targeting `wasm32-wasi`
3. Compile to `rns-core.wasm`
4. Replace Python sidecar with WASM sidecar
5. Validate with `benchmark/reticulum_bench.py`

### Phase 2 → Phase 3 Migration Path

1. Cross-compile `wasm3` with OpenWatcom for Win98
2. Create `rns-bridge.exe` Win98 wrapper
3. Package in QEMU disk image via `scripts/create_win98_image.sh`
4. Game state sync via memory-mapped file or named pipe
5. Remove sidecar entirely—mesh runs inside guests

## Alternative Lightweight Runtimes

Beyond WASM, these runtimes could host Reticulum primitives on constrained
platforms:

| Runtime | Target | Size | Use Case |
|---------|--------|------|----------|
| MicroPython | Win98 (via DOS) | ~300 KB | If Python subset sufficient |
| QuickJS | Win98 (native) | ~600 KB | JS engine, could run AssemblyScript output |
| Lua/LuaJIT | Win98 (native) | ~200 KB | Lightweight scripting |
| TinyGo | WASM | ~1 MB | Go subset compiling to small WASM |
| Zig | WASM/native | ~100 KB | Zero-overhead, targets i686 |

### QuickJS + AssemblyScript Path

```
AssemblyScript (TypeScript subset)
       │
       ▼
  WASM module (rns-core.wasm)
       │
       ▼
  QuickJS on Win98
  (runs JS glue + WASM loader)
```

This path allows developers to write Reticulum logic in TypeScript, compile
to WASM, and run it on Win98 via QuickJS—a JavaScript engine small enough for
Win98.

## Benchmark Integration

The WASM portability options are validated by the benchmark harness at
`benchmark/reticulum_bench.py`.  The `--mode` flag selects which runtime to
benchmark:

```bash
# Benchmark Python sidecar (Phase 1)
python3 benchmark/reticulum_bench.py --mode python

# Benchmark WASM sidecar (Phase 2)
python3 benchmark/reticulum_bench.py --mode wasm

# Benchmark native WASM in guest (Phase 3)
python3 benchmark/reticulum_bench.py --mode guest
```

## References

- [wasm3 – Fast WASM interpreter in C](https://github.com/nicedoc/wasm3)
- [Reticulum Python Reference](https://markqvist.github.io/Reticulum/manual/reference.html)
- [AssemblyScript](https://www.assemblyscript.org/)
- [QuickJS](https://bellard.org/quickjs/)
- [WASI – WebAssembly System Interface](https://wasi.dev/)
- [OpenWatcom – Win98-compatible C compiler](https://open-watcom.github.io/)

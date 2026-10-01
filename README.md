# openresty-ppc64le

**Unofficial, build-focused ppc64le (IBM Power) OpenResty binaries and Docker images. Caveat emptor.**

This is not an OpenResty release channel. It exists so the Power community can test OpenResty on ppc64le while the LuaJIT PPC64 fix is reviewed upstream:

- Issue: https://github.com/openresty/openresty/issues/1152
- Fix (draft, LLM-assisted, unreviewed): https://github.com/openresty/luajit2/pull/279

OpenResty 1.31.1.1 on ppc64le returns `0LL` from `ffi.cast("int64_t", n)`, which silently breaks `ngx.re`. These builds replace the bundled LuaJIT with a patched luajit2 ref.

## What you get

- Image: `ghcr.io/neomantra/openresty-ppc64le:<tag>`
- Tarball: the `/usr/local/openresty` install tree, attached to each release
- LuaJIT runs interpreter-only (no JIT, FFI kept); PCRE JIT is on
- Base: UBI 9

## Validation status

Releases say whether they were built **emulated** (QEMU) or **native**. Only native runs count as validated. Native POWER runners are not yet available (IBM actionspz).

## Build and test locally

```sh
docker buildx build --platform linux/ppc64le --load --target runtime -t openresty-ppc64le:dev .
docker run --rm --platform linux/ppc64le openresty-ppc64le:dev smoke.sh
```

Build args: `OPENRESTY_VERSION`, `LUAJIT_REPO`, `LUAJIT_REF`. Once the fix is upstream, point `LUAJIT_REPO`/`LUAJIT_REF` at luajit2 master.

## Reporting results

On real POWER hardware, run `docker run --rm ghcr.io/neomantra/openresty-ppc64le:<tag> smoke.sh` and comment on issue #1152 with `uname -m`, your distro, `gcc --version`, and the smoke output. Paste the full output if anything fails.

## Maintainers

- New GHCR packages start private. After the first tag push, make `openresty-ppc64le` public (Package settings -> Change visibility) or the pull command above will be denied for everyone else.
- The OpenResty source tarball is pinned by SHA-256 (`OPENRESTY_SHA256` in the Dockerfile, trust on first use). Update it together with `OPENRESTY_VERSION`.
- Release workflow runs refuse a `luajit_ref` override, so every release is built from the Dockerfile's default ref.

## Copyright & License

`openresty-ppc64le` is licensed under the 2-clause BSD license.

Copyright (c) 2026, Evan Wies evan@neomantra.net.

This module is licensed under the terms of the BSD license.

Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

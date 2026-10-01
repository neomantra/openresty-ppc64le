# openresty-ppc64le Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a separate repo that produces ppc64le OpenResty 1.31.1.1 binaries (tarball) and a Docker image with the PPC64 LuaJIT number-conversion fix, plus smoke tests that catch the regression.

**Architecture:** One multi-stage Dockerfile (UBI9) builds OpenResty with the bundled LuaJIT replaced by a pinned luajit2 ref. A scratch `export` stage yields the install tree, and a `ubi9-minimal` `runtime` stage is the image. `scripts/smoke.sh` runs inside the image. GitHub Actions builds under QEMU and keeps `runs-on` as an input for native runners later.

**Tech Stack:** Docker buildx, QEMU user emulation, UBI 9, OpenResty 1.31.1.1, luajit2 (neomantra fork), GitHub Actions, GHCR, bash.

**Spec:** `docs/superpowers/specs/2026-10-01-openresty-ppc64le-design.md`

## Global Constraints

- Target platform: `linux/ppc64le` only. One distro: UBI 9 (build `registry.access.redhat.com/ubi9`, runtime `registry.access.redhat.com/ubi9-minimal`).
- OpenResty version default: `1.31.1.1` (build arg `OPENRESTY_VERSION`).
- LuaJIT: build args `LUAJIT_REPO` (default `https://github.com/neomantra/openresty-luajit2.git`) and `LUAJIT_REF` (default `d18fd8f681f644f83eee28bf63b1cf4b1be44cda`).
- LuaJIT is interpreter-only (`-DLUAJIT_DISABLE_JIT`), FFI kept. PCRE JIT on.
- `git` must remain on PATH during `make`, because LuaJIT derives its version stamp from the git log.
- Repo `github.com/neomantra/openresty-ppc64le`; image `ghcr.io/neomantra/openresty-ppc64le`.
- Unofficial: README carries a `caveat emptor` notice. Runs are labeled `emulated` or `native`, and only native runs are called validated.
- Dropping the patch must be a one-line change (`LUAJIT_REF`).

## Review Focus

- Unpatched ref (`v2.1-20260914` from openresty/luajit2) built with the guard on: build must fail loudly, not ship a broken image. (Task 1)
- Unpatched ref built with the guard off (negative control): smoke must exit non-zero and print the failing command and output. (Task 1)
- Value above 2^31 (for example `4294967296`) and a negative value (`-5`) through `int64_t` casts: must round-trip, not become 0. (Task 1)
- `ngx.re.match` with no match: must return `nil` without error, not be confused with the broken-`ngx.re` failure. (Task 1)
- `git` missing at build time: build fails with a clear message, not a mangled version stamp. (Task 1)
- Emulated run described as validated: release notes must say `emulated`. (Task 2)

Each of these is tested in the owning task below.

---

### Task 1: Dockerfile, nginx config, and smoke tests

**Files:**
- Create: `Dockerfile`
- Create: `conf/nginx.conf`
- Create: `scripts/smoke.sh`
- Create: `.dockerignore`

**Interfaces:**
- Produces: image stages `build`, `export`, `runtime`. Build args `OPENRESTY_VERSION`, `LUAJIT_REPO`, `LUAJIT_REF`, `REQUIRE_PPC64_FIX` (default `1`). `scripts/smoke.sh` takes no args and exits 0 on pass, non-zero with the failing command printed on failure. It expects `openresty` and `resty` on PATH and `curl` available.
- Consumes: nothing.

- [ ] **Step 1: Write `scripts/smoke.sh` (the failing test)**

```bash
#!/usr/bin/env bash
# Smoke tests for the ppc64le LuaJIT number-conversion regression.
# Run inside the built image. Exits non-zero on the first failure.
set -u

fail=0
check() {
  local name="$1" expected="$2"; shift 2
  local out
  out="$("$@" 2>&1)"
  if [ "$out" = "$expected" ]; then
    echo "PASS  $name"
  else
    echo "FAIL  $name"
    echo "  command : $*"
    echo "  expected: $expected"
    echo "  actual  : $out"
    fail=1
  fi
}

LJ=/usr/local/openresty/luajit/bin/luajit

# 1. 64-bit FFI casts round-trip (the regression: these returned 0).
for t in int64_t uint64_t intptr_t; do
  check "ffi.cast $t 123456789" "123456789" \
    $LJ -e "local ffi=require('ffi'); print(tonumber(ffi.cast('$t', 123456789)))"
done
check "ffi.cast int64_t above 2^31" "4294967296" \
  $LJ -e "local ffi=require('ffi'); print(tonumber(ffi.cast('int64_t', 4294967296)))"
check "ffi.cast int64_t negative" "-5" \
  $LJ -e "local ffi=require('ffi'); print(tonumber(ffi.cast('int64_t', -5)))"

# 2. ipairs visits every element (the regression: visited 1).
check "ipairs count" "9" \
  $LJ -e "local n=0; for _ in ipairs({1,2,10,100,255,256,1000,123456789,2147483647}) do n=n+1 end; print(n)"

# 3. ngx.re works through resty (the regression: silently returned nil).
check "ngx.re.match jo" "12345" \
  resty -e 'local m = ngx.re.match("hello 12345 world", [[(\d+)]], "jo"); print(m and m[1])'
check "ngx.re.match no match is nil" "nil" \
  resty -e 'local m = ngx.re.match("hello world", [[(\d+)]], "jo"); print(m)'

# 4. nginx config is valid and serves a request.
check "nginx -t" "ok" bash -c 'openresty -t >/dev/null 2>&1 && echo ok'
openresty -g 'daemon on;'
sleep 1
check "http request" "hello from openresty" curl -fsS http://127.0.0.1:8080/
openresty -s stop >/dev/null 2>&1

exit "$fail"
```

- [ ] **Step 2: Write `conf/nginx.conf`**

```nginx
worker_processes 1;
error_log /dev/stderr info;
pid /tmp/nginx.pid;

events { worker_connections 256; }

http {
    access_log /dev/stdout;
    server {
        listen 8080;
        location / {
            default_type text/plain;
            content_by_lua_block { ngx.say("hello from openresty") }
        }
    }
}
```

- [ ] **Step 3: Write `.dockerignore`**

```
.git
docs
```

- [ ] **Step 4: Run the smoke test to verify it fails with no image**

Run: `bash scripts/smoke.sh`
Expected: FAIL lines (no `luajit`/`resty` on this host); exit status 1. This confirms the script reports failures rather than passing vacuously.

- [ ] **Step 5: Write `Dockerfile`**

```dockerfile
ARG OPENRESTY_VERSION=1.31.1.1

FROM registry.access.redhat.com/ubi9 AS build
ARG OPENRESTY_VERSION
ARG LUAJIT_REPO=https://github.com/neomantra/openresty-luajit2.git
ARG LUAJIT_REF=d18fd8f681f644f83eee28bf63b1cf4b1be44cda
# Set to 0 only for the negative control (building an unpatched LuaJIT).
ARG REQUIRE_PPC64_FIX=1

RUN dnf install -y gcc gcc-c++ make perl git curl tar gzip patch which \
        pcre2-devel openssl-devel zlib-devel \
    && dnf clean all \
    && command -v git >/dev/null || { echo "git is required during make" >&2; exit 1; }

WORKDIR /src
RUN curl -fsSL "https://openresty.org/download/openresty-${OPENRESTY_VERSION}.tar.gz" \
    | tar xz --strip-components=1

# Replace the bundled LuaJIT (directory name must match bundle/LuaJIT-[0-9]*).
RUN LJDIR="$(ls -d bundle/LuaJIT-[0-9]* | head -n1)" \
    && rm -rf "$LJDIR" \
    && git clone "$LUAJIT_REPO" "$LJDIR" \
    && git -C "$LJDIR" checkout "$LUAJIT_REF" \
    && if [ "$REQUIRE_PPC64_FIX" = "1" ]; then \
         grep -q fctidz "$LJDIR/src/vm_ppc.dasc" \
           || { echo "LUAJIT_REF lacks the PPC64 64-bit conversion fix (no fctidz in vm_ppc.dasc)" >&2; exit 1; }; \
       fi

RUN ./configure --prefix=/usr/local/openresty \
        --with-pcre-jit --with-http_ssl_module \
        --with-luajit-xcflags='-DLUAJIT_DISABLE_JIT' \
        -j"$(nproc)" \
    && make -j"$(nproc)" \
    && make install

FROM scratch AS export
COPY --from=build /usr/local/openresty /usr/local/openresty

FROM registry.access.redhat.com/ubi9-minimal AS runtime
RUN microdnf install -y pcre2 openssl-libs zlib curl-minimal \
    && microdnf clean all
COPY --from=build /usr/local/openresty /usr/local/openresty
COPY conf/nginx.conf /usr/local/openresty/nginx/conf/nginx.conf
COPY scripts/smoke.sh /usr/local/bin/smoke.sh
ENV PATH=/usr/local/openresty/bin:/usr/local/openresty/luajit/bin:$PATH
EXPOSE 8080
CMD ["openresty", "-g", "daemon off;"]
```

If `./configure` rejects `-j` or a flag, drop it or adjust; the compile flags in Global Constraints (`-DLUAJIT_DISABLE_JIT`, `--with-pcre-jit`) are the requirement.

- [ ] **Step 6: Negative control with the guard on: build must fail loudly**

Run:
```bash
docker buildx build --platform linux/ppc64le \
  --build-arg LUAJIT_REPO=https://github.com/openresty/luajit2.git \
  --build-arg LUAJIT_REF=v2.1-20260914 \
  --target build -t ppc64le-guard-test .
```
Expected: FAIL, with `LUAJIT_REF lacks the PPC64 64-bit conversion fix`. It fails in seconds, before the long compile. If this passes, the grep pattern is wrong. Re-inspect `src/vm_ppc.dasc`.

- [ ] **Step 7: Negative control with the guard off: smoke must fail**

Run:
```bash
docker buildx build --platform linux/ppc64le --load \
  --build-arg LUAJIT_REPO=https://github.com/openresty/luajit2.git \
  --build-arg LUAJIT_REF=v2.1-20260914 \
  --build-arg REQUIRE_PPC64_FIX=0 \
  --target runtime -t openresty-ppc64le:unpatched .
docker run --rm --platform linux/ppc64le openresty-ppc64le:unpatched smoke.sh
```
Expected: slow under QEMU (an hour or more). Smoke exits non-zero with `FAIL  ffi.cast int64_t 123456789` showing `actual  : 0`, and `FAIL  ipairs count` showing `1`. Record the output; it is the demonstration for success criterion 2.

- [ ] **Step 8: Patched build: smoke must pass**

Run:
```bash
docker buildx build --platform linux/ppc64le --load \
  --target runtime -t openresty-ppc64le:dev .
docker run --rm --platform linux/ppc64le openresty-ppc64le:dev smoke.sh
```
Expected: every line `PASS`, exit 0. If `nginx -t` or the curl check fails only because of QEMU timing, raise `sleep 1` to `sleep 3` in `scripts/smoke.sh`.

- [ ] **Step 9: Verify the tarball export**

Run: `docker buildx build --platform linux/ppc64le --target export --output type=tar,dest=openresty-ppc64le.tar . && tar tf openresty-ppc64le.tar | head`
Expected: entries under `usr/local/openresty/`.

- [ ] **Step 10: Commit**

```bash
git add Dockerfile conf scripts .dockerignore
git commit -m "feat: ppc64le OpenResty Dockerfile with patched LuaJIT and smoke tests"
```

---

### Task 2: GitHub Actions CI and release

**Files:**
- Create: `.github/workflows/build.yml`

**Interfaces:**
- Consumes: the Dockerfile stages `export` and `runtime`, and `scripts/smoke.sh` (installed in the image at `/usr/local/bin/smoke.sh`), from Task 1.
- Produces: a workflow with `workflow_dispatch` inputs `runs-on` (default `ubuntu-latest`) and `luajit_ref` (default empty, meaning use the Dockerfile default). On `v*` tags it pushes `ghcr.io/neomantra/openresty-ppc64le:<tag>` and creates a release with the tarball.

- [ ] **Step 1: Write the workflow**

```yaml
name: build

on:
  workflow_dispatch:
    inputs:
      runs-on:
        description: Runner label (use a native ppc64le runner when available)
        default: ubuntu-latest
      luajit_ref:
        description: Override LUAJIT_REF (empty = Dockerfile default)
        default: ""
  push:
    branches: [main]
    tags: ['v*']

env:
  IMAGE: ghcr.io/neomantra/openresty-ppc64le

jobs:
  build:
    runs-on: ${{ inputs.runs-on || 'ubuntu-latest' }}
    timeout-minutes: 360
    permissions:
      contents: write
      packages: write
    steps:
      - uses: actions/checkout@v4

      - name: Classify run
        id: kind
        run: |
          if [ "$(uname -m)" = "ppc64le" ]; then echo "kind=native" >> "$GITHUB_OUTPUT"
          else echo "kind=emulated" >> "$GITHUB_OUTPUT"; fi

      - uses: docker/setup-qemu-action@v3
        if: steps.kind.outputs.kind == 'emulated'
      - uses: docker/setup-buildx-action@v3

      - name: Build image
        run: |
          ARGS=""
          if [ -n "${{ inputs.luajit_ref }}" ]; then ARGS="--build-arg LUAJIT_REF=${{ inputs.luajit_ref }}"; fi
          docker buildx build --platform linux/ppc64le --load $ARGS \
            --target runtime -t "$IMAGE:ci" .

      - name: Smoke tests
        run: docker run --rm --platform linux/ppc64le "$IMAGE:ci" smoke.sh

      - name: Export tarball
        run: |
          docker buildx build --platform linux/ppc64le --target export \
            --output type=tar,dest=openresty-ppc64le.tar .
          gzip -f openresty-ppc64le.tar

      - uses: actions/upload-artifact@v4
        with:
          name: openresty-ppc64le-${{ steps.kind.outputs.kind }}
          path: openresty-ppc64le.tar.gz

      - name: Log in to GHCR
        if: startsWith(github.ref, 'refs/tags/v')
        uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - name: Push image
        if: startsWith(github.ref, 'refs/tags/v')
        run: |
          docker tag "$IMAGE:ci" "$IMAGE:${GITHUB_REF_NAME}"
          docker push "$IMAGE:${GITHUB_REF_NAME}"

      - name: Release
        if: startsWith(github.ref, 'refs/tags/v')
        uses: softprops/action-gh-release@v2
        with:
          files: openresty-ppc64le.tar.gz
          body: |
            UNOFFICIAL ppc64le build (caveat emptor). Built **${{ steps.kind.outputs.kind }}**.
            ${{ steps.kind.outputs.kind == 'emulated' && 'Emulated under QEMU: not validated on native POWER hardware.' || 'Built and smoke-tested on native ppc64le.' }}
```

- [ ] **Step 2: Lint the workflow**

Run: `docker run --rm -v "$PWD":/repo -w /repo rhysd/actionlint:latest`
Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add .github
git commit -m "ci: build, smoke-test and release under QEMU or native runners"
```

---

### Task 3: README and publish

**Files:**
- Create: `README.md`

**Interfaces:**
- Consumes: image name, build args, and smoke script from Tasks 1 and 2.
- Produces: the public repo `github.com/neomantra/openresty-ppc64le`.

- [ ] **Step 1: Write `README.md`**

````markdown
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

On real POWER hardware, please run `smoke.sh` and comment on issue #1152 with `uname -m`, your distro, `gcc --version`, and the smoke output. Paste the full output if anything fails.
````

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "docs: README with caveat emptor and reporting instructions"
```

- [ ] **Step 3: Confirm before publishing**

Creating the GitHub repo and pushing is outward-facing. Ask the user to confirm, then run:
```bash
gh repo create neomantra/openresty-ppc64le --public --source . --push
```
Then dispatch one workflow run: `gh workflow run build.yml` and watch it with `gh run watch`.
Expected: green run, artifact `openresty-ppc64le-emulated`.

---

## Self-Review

- **Spec coverage:** the Dockerfile stages, build args, guard, smoke tests, negative control, CI with `runs-on` input, release labeling, and README are each covered by tasks above. The spec's "grep for the 64-bit helpers" is implemented as `grep fctidz`, taken from the actual fix commit.
- **Placeholders:** none. The `REQUIRE_PPC64_FIX` arg is a spec addition that makes the negative control possible.
- **Consistency:** the names `OPENRESTY_VERSION`, `LUAJIT_REPO`, `LUAJIT_REF`, `REQUIRE_PPC64_FIX`, the stages, and `/usr/local/bin/smoke.sh` match across tasks.

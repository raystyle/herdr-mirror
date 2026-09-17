#!/usr/bin/env bash
# build-release 标准三段式之第一、二段:本地编译打包 + gh release 直发。
# 标准见 project-evo plugins/evo-adr/skills/build-release/。
# 平台矩阵(用户裁定 2026-09-17):仅 linux+mac 双端,包形 tar.gz 单形,无 win 腿。
# 矩阵仓裁:linux x86_64-gnu 本职、linux aarch64-gnu 交叉(标准扩岗);
#           darwin 双端在 mac 实机编(ssh lan-mac,aria2 家族同款工位)。
# 用法:scripts/release.sh <vX.Y.Z> [--dry-run]
#   --dry-run:走完闸、编译、打包、冒烟,不建 Release(实弹前演练)。
# 播种不在本脚本:Release published 事件自动触发 .github/workflows/r2-seed.yml。
set -euo pipefail
cd "$(dirname "$0")/.."

TAG="${1:?用法: scripts/release.sh <vX.Y.Z> [--dry-run]}"
DRY_RUN="${2:-}"
VER="${TAG#v}"
MAC_SSH="${MAC_SSH:-lan-mac}"
MAC_DIR="${MAC_DIR:-build/herdr-mirror}" # remote home-relative

say() { printf '\n== %s ==\n' "$*"; }
die() { echo "release: $*" >&2; exit 1; }

# 1 版本一致性闸:tag 对双载体 manifest,不一致即止
say "版本一致性闸 (tag=$TAG)"
cv="$(sed -n 's/^version = "\(.*\)"/\1/p' Cargo.toml | head -1)"
pv="$(sed -n 's/^version = "\(.*\)"/\1/p' herdr-plugin.toml | head -1)"
[ "$cv" = "$VER" ] || die "Cargo.toml=$cv != $VER"
[ "$pv" = "$VER" ] || die "herdr-plugin.toml=$pv != $VER"

# 2 测试闸先行
say "测试闸 cargo test --locked"
cargo test --locked

# 3 本地编译:linux 双端
say "本地编译 linux 双端 (x86_64-gnu 本职, aarch64-gnu 交叉)"
cargo build --release --locked --target x86_64-unknown-linux-gnu
CARGO_TARGET_AARCH64_UNKNOWN_LINUX_GNU_LINKER=aarch64-linux-gnu-gcc \
  cargo build --release --locked --target aarch64-unknown-linux-gnu

# 4 mac 实机编译 darwin 双端(aarch64 实机跑 --version;x86_64 在无 Rosetta 宿主
#   回退 file 结构冒烟——交叉件冒烟的标准仓裁形)
say "mac 实机编译 ($MAC_SSH)"
rsync -a --delete --exclude target --exclude dist --exclude .git --exclude .macbin ./ "$MAC_SSH:$MAC_DIR/"
ssh "$MAC_SSH" "cd '$MAC_DIR' && \
  cargo build --release --locked --target x86_64-apple-darwin && \
  cargo build --release --locked --target aarch64-apple-darwin && \
  ./target/aarch64-apple-darwin/release/herdr-mirror --version && \
  { ./target/x86_64-apple-darwin/release/herdr-mirror --version || \
    file ./target/x86_64-apple-darwin/release/herdr-mirror | grep -q 'Mach-O 64-bit executable x86_64'; }"
mkdir -p .macbin
scp -q "$MAC_SSH:$MAC_DIR/target/x86_64-apple-darwin/release/herdr-mirror" .macbin/darwin-x86_64
scp -q "$MAC_SSH:$MAC_DIR/target/aarch64-apple-darwin/release/herdr-mirror" .macbin/darwin-aarch64

# 5 打包:单顶层目录 tar.gz(二进制+README+LICENSE),逐包边车 + 聚合补充
say "打包 (tar.gz 单形,逐包 .sha256 边车)"
rm -rf dist && mkdir -p dist
pkg() { # <os> <arch> <srcbin>
  local name="herdr-mirror-${VER}-$1-$2"
  local dir="dist/${name}"
  mkdir -p "$dir"
  cp "$3" "$dir/herdr-mirror"
  cp README.md LICENSE "$dir/"
  (cd dist && tar czf "${name}.tar.gz" "$name" && rm -rf "$name" \
    && sha256sum "${name}.tar.gz" > "${name}.tar.gz.sha256")
  echo "  dist/${name}.tar.gz"
}
pkg linux x86_64  target/x86_64-unknown-linux-gnu/release/herdr-mirror
pkg linux aarch64 target/aarch64-unknown-linux-gnu/release/herdr-mirror
pkg darwin x86_64  .macbin/darwin-x86_64
pkg darwin aarch64 .macbin/darwin-aarch64
(cd dist && sha256sum *.tar.gz > SHA256SUMS)

# 6 解包冒烟:解出跑 --version 与 VER 逐字对(aarch64 无 qemu 则留目标实机,darwin 已随编)
say "解包冒烟"
for f in dist/*.tar.gz; do
  tmp="$(mktemp -d)"
  tar xzf "$f" -C "$tmp"
  bin="$(find "$tmp" -mindepth 2 -maxdepth 2 -type f -name herdr-mirror)"
  [ -n "$bin" ] || die "解包未见二进制: $f"
  case "$f" in
    *linux-x86_64*)
      out="$("$bin" --version)" ;;
    *linux-aarch64*)
      if command -v qemu-aarch64-static >/dev/null 2>&1; then
        out="$(qemu-aarch64-static -L /usr/aarch64-linux-gnu "$bin" --version)"
      else
        echo "  $f: 无 qemu,冒烟留目标实机"; continue
      fi ;;
    *darwin-*)
      echo "  $f: darwin 冒烟已在 mac 实机随编译过(aarch64 实跑,x86_64 结构断言)"; continue ;;
  esac
  [ "$out" = "herdr-mirror $VER" ] || die "冒烟不符: $f -> $out"
  echo "  $f: $out"
done

if [ "$DRY_RUN" = "--dry-run" ]; then
  say "DRY RUN 止步(未建 Release)"
  ls -l dist/
  exit 0
fi

# 7 GitHub 产物发布:gh 直发钉 latest,禁 draft
say "gh release create $TAG --latest"
gh release create "$TAG" dist/* --latest \
  --title "herdr-mirror $TAG" \
  --notes "linux+mac 双端 tar.gz,逐包 .sha256 边车为锚;镜像段随 Release 自动播种。"
say "完成:$TAG(播种看 r2-seed workflow)"

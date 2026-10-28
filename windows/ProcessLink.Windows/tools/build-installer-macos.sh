#!/bin/zsh
# Experimental cross-build of the Windows NSIS installer from macOS.
# Uses cargo-xwin + LLVM's llvm-rc + makensis. The supported path is the
# GitHub Actions windows-latest job, which also builds the MSI.
set -euo pipefail
here=${0:A:h}
root=${here:h}
repo=${root:h:h}
version="${1:-0.1.0}"
target="x86_64-pc-windows-msvc"
export PATH="/opt/homebrew/opt/llvm/bin:$HOME/.cargo/bin:$PATH"
command -v cargo-xwin >/dev/null || { echo "cargo-xwin is required (cargo install cargo-xwin --locked)"; exit 1; }
command -v makensis >/dev/null || { echo "makensis is required (brew install makensis)"; exit 1; }
[[ -f "$repo/web/dist/index.html" ]] || { echo "build the web bundle first: npm --prefix web run build"; exit 1; }

cd "$root/src-tauri"
cargo xwin build --release --target "$target"
exe="target/$target/release/processlink.exe"
[[ -f "$exe" ]] || { echo "missing $exe"; exit 1; }

stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
cp "$exe" "$stage/processlink.exe"
cp icons/icon.ico "$stage/icon.ico"
mkdir -p "$root/dist"
out="$root/dist/ProcessLink-$version-x64-setup.exe"
makensis -V2 -DVERSION="$version" -DSRCDIR="$stage" -DOUTFILE="$out" "$root/tools/installer.nsi"
shasum -a 256 "$out" | awk '{print $1"  '"$(basename "$out")"'"}' > "$out.sha256"
echo "==> $out"
ls -lh "$out"

#!/usr/bin/env bash
# Simulator + serve-sim の起動を冪等に保証する。
# 既に Booted & serve-sim 稼働中なら何もせず接続情報を表示。
#
#   ensure-sim.sh                 # 唯一の Booted 端末に serve-sim をアタッチ
#   ensure-sim.sh "iPhone 17"     # 指定機種を（未起動ならブートして）使う
#   ensure-sim.sh <UDID>          # UDID 直指定
#
# 機種名は同名の端末が複数あるとき Booted を優先し、無ければ OS 最新を選ぶ。
# 出力 `SIM_BASE=... SIM_WS=... SIM_UDID=...` は eval + export すると
# 後続スクリプトが接続先解決（毎回数秒）を省略できる。
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
source "$DIR/lib.sh"

# 環境に残った接続情報で sim_resolve が早期リターンすると起動保証にならないため破棄する
unset SIM_BASE SIM_WS SIM_UDID

want="${1:-}"

# 1. 対象端末を決める。
#    - 機種名指定あり: 同名端末から Booted 優先→OS 最新で UDID を解決し、未 Boot ならブート。
#    - UDID 指定あり: 実在を確認してそのまま使う。
#    - 指定なし: 既存の Booted 端末をそのまま使う。
target=""
if [ -n "$want" ]; then
  if sim_is_udid "$want"; then
    xcrun simctl list devices -j 2>/dev/null | grep -qiF "\"$want\"" \
      || { echo "UDID に一致する端末が見つかりません: $want" >&2; exit 2; }
    target="$want"
  else
    target=$(sim_name_to_udid "$want") \
      || { echo "機種名に一致する利用可能な端末が見つかりません: $want" >&2; exit 2; }
  fi
  if ! xcrun simctl list devices booted 2>/dev/null | grep -qi "$target"; then
    echo "ブート中: $want ($target)" >&2
    xcrun simctl boot "$target"
  fi
else
  booted_count=$(xcrun simctl list devices booted 2>/dev/null | grep -c "(Booted)" || true)
  if [ "$booted_count" -eq 0 ]; then
    echo "Booted 端末なし。起動する機種名を引数で指定してください" >&2
    exit 2
  elif [ "$booted_count" -gt 1 ]; then
    echo "Booted 端末が複数あります。使用する機種名を引数で指定してください" >&2
    exit 2
  fi
fi

# 以降は解決済み UDID（target）で一意に扱う。未指定時は空のまま唯一の Booted を使う。

# 2. serve-sim が稼働していればそのまま、なければ detach 起動
if ! sim_resolve "$target" 2>/dev/null; then
  echo "serve-sim を detach 起動" >&2
  npx "$SERVE_SIM_PKG" --detach -q ${target:+"$target"} >/dev/null 2>&1 || true
  ok=""
  for _ in 1 2 3 4 5; do
    if sim_resolve "$target" 2>/dev/null; then ok=1; break; fi
    sleep 1
  done
  # リトライ全滅時のみ再解決して失敗理由（複数台で非一意 等）を stderr に出す
  [ -n "$ok" ] || sim_resolve "$target" || { echo "serve-sim の起動に失敗" >&2; exit 1; }
fi

echo "SIM_BASE=$SIM_BASE SIM_WS=$SIM_WS SIM_UDID=$SIM_UDID"

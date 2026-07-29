#!/usr/bin/env bash
# serve-sim の接続先を解決する共通ヘルパー。各スクリプトから source して使う。
#
#   source "$(dirname "$0")/lib.sh"
#   sim_resolve [device]   # → SIM_BASE / SIM_WS / SIM_UDID を export
#
# device は機種名（例: "iPhone 17"）・UDID・UDID の一部。
# 省略時は環境変数 SIM_DEVICE、それも無ければ唯一の Booted 端末を使う。

SIM_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# serve-sim は動作確認済みバージョンに固定する。latest 追従だと、依存している
# 非公開挙動（gesture の begin/end 分割 = 長押し判定 等）が更新で変わった際に
# 全操作がサイレントに壊れるため。更新時は動作確認の上でここを上げる。
# ax_tools.py（resolve_base の既定値）も同じバージョンに揃えること。
SERVE_SIM_PKG="${SERVE_SIM_PKG:-serve-sim@0.1.44}"
export SERVE_SIM_PKG

# Simulator の UDID 形式（8-4-4-4-12 の16進）かどうか
sim_is_udid() { printf '%s' "$1" | grep -qiE '^[0-9A-F]{8}(-[0-9A-F]{4}){3}-[0-9A-F]{12}$'; }

# 先頭の -d <device> 引数を取り込む共通パース。値は $SIM_DEV（未指定なら空）。
#   sim_parse_dev "$@" || usage
#   shift "$SIM_DEV_SHIFT"
sim_parse_dev() {
  SIM_DEV=""; SIM_DEV_SHIFT=0
  if [ "${1:-}" = "-d" ]; then
    [ "$#" -ge 2 ] || return 1
    SIM_DEV="$2"; SIM_DEV_SHIFT=2
  fi
}

# 機種名 → UDID を解決する。利用可能な端末のうち、機種名が完全一致するものから
# Booted を優先し、無ければ OS バージョンが最新のものを選ぶ。
# 見つかれば UDID を1行出力して 0、見つからなければ何も出さず 1 を返す。
# （引数が機種名に一致しない場合も 1 を返すので、呼び出し側で fallback する）
sim_name_to_udid() {
  local name="$1"
  [ -n "$name" ] || return 1
  xcrun simctl list devices -j 2>/dev/null | SIM_NAME="$name" python3 -c '
import sys, json, os, re
name = os.environ.get("SIM_NAME") or ""
try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(1)
cands = []  # (booted, version_tuple, udid)
for runtime, devices in (data.get("devices") or {}).items():
    nums = re.findall(r"\d+", runtime.split(".")[-1])
    ver = tuple(int(n) for n in nums) if nums else (0,)
    for d in devices:
        if not d.get("isAvailable", False):
            continue
        if d.get("name") != name:
            continue
        booted = 1 if d.get("state") == "Booted" else 0
        cands.append((booted, ver, d.get("udid", "")))
if not cands:
    sys.exit(1)
# Booted 優先 → OS バージョン最新
cands.sort(key=lambda c: (c[0], c[1]), reverse=True)
print(cands[0][2])
'
}

# 成功時 0。接続先候補が無ければ 1、複数台で一意に定まらなければ 2 を返す
# （2 のときは案内メッセージを stderr に出力済み）。
sim_resolve() {
  local want="${1:-${SIM_DEVICE:-}}"
  # 機種名なら UDID に解決（同名複数は Booted 優先→OS 最新）。
  # UDID 形式はそのまま、機種名に一致しない文字列は下の substring 一致に回す。
  if [ -n "$want" ] && ! sim_is_udid "$want"; then
    local udid
    if udid=$(sim_name_to_udid "$want") && [ -n "$udid" ]; then
      want="$udid"
    fi
  fi
  # 解決済みの接続情報が環境にあれば npx（毎回数秒）を省略する。別端末指定時は解決し直す。
  if [ -n "${SIM_BASE:-}" ] && [ -n "${SIM_WS:-}" ] && [ -n "${SIM_UDID:-}" ]; then
    if [ -z "$want" ] || [ "$want" = "$SIM_UDID" ]; then
      export SIM_BASE SIM_WS SIM_UDID
      return 0
    fi
  fi
  local out
  # --list 出力のパースと base 導出の実体は ax_tools.py の resolve に一本化してある
  out=$(npx "$SERVE_SIM_PKG" --list -q 2>/dev/null \
    | python3 "$SIM_LIB_DIR/ax_tools.py" resolve --want "$want") || return $?
  SIM_BASE=$(printf '%s\n' "$out" | awk 'NR==1')
  SIM_WS=$(printf '%s\n' "$out" | awk 'NR==2')
  SIM_UDID=$(printf '%s\n' "$out" | awk 'NR==3')
  export SIM_BASE SIM_WS SIM_UDID
  [ -n "$SIM_BASE" ]
}

# sim_resolve の失敗時に案内を出して exit 2 する版。各スクリプトの入口で使う。
sim_resolve_or_die() {
  local rc=0
  sim_resolve "$@" || rc=$?
  if [ "$rc" -eq 2 ]; then
    # 複数台で一意に定まらない旨は sim_resolve が stderr に案内済み（未起動ではない）
    exit 2
  elif [ "$rc" -ne 0 ]; then
    echo "serve-sim 未起動。ensure-sim.sh を先に実行" >&2
    exit 2
  fi
}

# サブコマンドに付ける -d 引数（解決済みなら付与）。`npx "$SERVE_SIM_PKG" tap x y $(sim_dflag)`
# 未解決でも 0 を返す（`DFLAG=$(sim_dflag)` の代入で set -e を発火させないため）。
sim_dflag() { if [ -n "${SIM_UDID:-}" ]; then printf -- '-d\n%s\n' "$SIM_UDID"; fi; }

# gesture.cjs（単一 WS 接続ドラッグ）を実行する。drag.sh / scroll.sh 共通。
# ws モジュールは serve-sim が npx キャッシュに持つものを借用する
# （探索結果はファイルにキャッシュし、操作のたびのキャッシュ全走査を避ける）。
sim_gesture() {  # 引数: <eventsJSON> <delayMs>
  local ws_dir="" cache="${TMPDIR:-/tmp}/control-ios-ws-dir"
  if [ -f "$cache" ]; then
    ws_dir=$(cat "$cache")
    [ -d "$ws_dir" ] || ws_dir=""
  fi
  if [ -z "$ws_dir" ]; then
    ws_dir=$(find ~/.npm/_npx -type d -name ws 2>/dev/null | head -1)
    if [ -z "$ws_dir" ]; then
      # find 空振りのまま dirname に通すと NODE_PATH="." になり原因の見えないエラーになるため明示 fail
      echo "npx キャッシュに ws モジュールが見つかりません。npx serve-sim --list を一度実行してください" >&2
      return 1
    fi
    printf '%s\n' "$ws_dir" >"$cache"
  fi
  NODE_PATH="$(dirname "$ws_dir")" node "$SIM_LIB_DIR/gesture.cjs" "$SIM_WS" "$1" "$2"
}

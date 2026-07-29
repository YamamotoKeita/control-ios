#!/usr/bin/env python3
"""serve-sim の AX ツリーを扱うユーティリティ。

サブコマンド:
  list                     画面内（正規化 0..1）の要素を type / 座標 / ラベル付きで一覧。
  anchor  <a1> [a2 ...]    在室判定。anchor のいずれかが画面内ラベルに部分一致すれば在室
                           （exit 0）。無ければ exit 1、AX 取得異常は exit 2。
  label   <文字列>         ラベルを正規化座標へ解決し "nx ny" を出力（exact 一致のみ）。
                           同名複数一致は失敗（--type / --index で絞る。--all で全件表示）。
  point   <px> <py>        AX ポイント座標を root frame で割って正規化し "nx ny" を出力。
  resolve [--want <s>]     `serve-sim --list -q` の JSON を stdin から受け、接続先の
                           BASE / WS / UDID を3行で出力（lib.sh sim_resolve の実体）。
                           候補なしは exit 1、複数台で非一意は exit 2。

ラベルの探索対象は AXLabel に加え AXValue / AXPlaceholderValue も見る
（プレースホルダ「キーワードで検索」等は AXValue で返るため）。

接続先は --base または環境変数 SIM_BASE。どちらも無ければ `serve-sim --list -q` から
lib.sh 相当の解決を行う（detach 構成の helper パス付き base に対応）。
--base / --ax-file はサブコマンドの前後どちらに置いてもよい。
取得済み AX を使い回すときは --ax-file <path> でファイルから読む。
"""
import argparse
import json
import os
import subprocess
import sys
import threading
import urllib.request

# AX ノードからラベル候補として拾うキー
LABEL_KEYS = ("AXLabel", "AXValue", "AXPlaceholderValue")
AX_NODE_CAP = 500  # serve-sim の /ax 返却上限。これに達したら取りこぼしを警告


def parse_streams(d, want=""):
    """`serve-sim --list -q` の JSON から stream の一覧を取り出す。

    --list -q は 1台時フラット / 複数台時 {"streams":[...]} を返す。
    want があれば device（UDID）への部分一致で絞る。
    """
    streams = d.get("streams") if isinstance(d, dict) and "streams" in d else [d]
    streams = [s for s in streams if isinstance(s, dict) and s.get("url")]
    if want:
        streams = [s for s in streams if want in str(s.get("device", ""))]
    return streams


def http_base(s):
    """stream の wsUrl から HTTP base を導出する。

    HTTP エンドポイント(/ax /config 等)は wsUrl と同じパス階層にある:
      単一時     ws://h:3100/ws                 -> http://h:3100
      複数helper ws://h:3101/helper/<udid>/ws   -> http://h:3101/helper/<udid>
    url は host:port のみで helper パスが落ちるため、wsUrl から導出する。
    """
    ws = s.get("wsUrl") or ""
    if not ws:
        return s.get("url", "")
    for scheme, http in (("ws://", "http://"), ("wss://", "https://")):
        if ws.startswith(scheme):
            ws = http + ws[len(scheme):]
            break
    return ws[: -len("/ws")] if ws.endswith("/ws") else ws


def resolve_base():
    """lib.sh の sim_resolve 相当。`serve-sim --list -q` の wsUrl から HTTP base を導出する。

    detach 構成では 1台でも base が http://host:3100/helper/<UDID> になるため、
    既定値 http://127.0.0.1:3100 への直アクセスは /ax がハングする。必ずこの解決を通す。
    接続先が特定できない（未起動 / 複数台）場合は None。
    """
    try:
        out = subprocess.run(
            # 動作確認済みバージョンに固定（lib.sh の SERVE_SIM_PKG と揃える）
            ["npx", os.environ.get("SERVE_SIM_PKG", "serve-sim@0.1.44"), "--list", "-q"],
            capture_output=True, text=True, timeout=30,
        ).stdout
        d = json.loads(out)
    except Exception:
        return None
    streams = parse_streams(d)
    if len(streams) != 1:
        # 複数台のまま先頭を選ぶと別端末を誤操作しうるため明示指定させる
        return None
    return http_base(streams[0])


def fetch_ax(base, timeout=10):
    """/ax を取得する。urlopen の timeout が効かないケース（ヘッダーのみ返して body が
    来ない等。root /ax への誤アクセスで実測）があるため、スレッドで総時間も打ち切る。"""
    result = {}

    def worker():
        try:
            with urllib.request.urlopen(base.rstrip("/") + "/ax", timeout=timeout) as r:
                result["data"] = json.load(r)
        except Exception as e:  # noqa: BLE001 呼び出し元に転送する
            result["error"] = e

    t = threading.Thread(target=worker, daemon=True)
    t.start()
    t.join(timeout + 2)
    if t.is_alive():
        raise TimeoutError(
            f"/ax が {timeout}s 以内に応答しません: {base} 。"
            "detach 構成の接続先は helper パス付き（例 http://127.0.0.1:3100/helper/<UDID>）。"
            "ensure-sim.sh の返す BASE を --base / SIM_BASE に指定してください"
        )
    if "error" in result:
        raise result["error"]
    return result["data"]


def load_ax(args):
    # AX の取得・パース失敗は exit 2 に寄せる。anchor の「非在室 = exit 1」と
    # 区別できないと、呼び出し側が接続断を画面遷移失敗と誤判定するため。
    try:
        if args.ax_file:
            # ローカルで開発者/エージェントが指定する信頼済みパスのみを読む補助CLIのため許容する
            # bearer:disable python_lang_path_traversal
            with open(args.ax_file, encoding="utf-8") as f:
                return json.load(f)
        base = args.base or os.environ.get("SIM_BASE") or resolve_base()
        if not base:
            print("接続先を解決できません（serve-sim 未起動 or 複数台）。ensure-sim.sh を実行し、"
                  "返る BASE を --base か SIM_BASE で指定してください", file=sys.stderr)
            sys.exit(2)
        return fetch_ax(base)
    except SystemExit:
        raise
    except Exception as e:
        print(f"AX の取得に失敗: {e}", file=sys.stderr)
        sys.exit(2)


def walk(node):
    """ツリーを深さ優先で巡回し各ノードを yield。"""
    yield node
    for c in node.get("children", []) or []:
        yield from walk(c)


def node_labels(node):
    """ノードのラベル候補（文字列）を返す。"""
    out = []
    for k in LABEL_KEYS:
        v = node.get(k)
        if isinstance(v, str) and v:
            out.append(v)
    return out


def norm_center(node, w, h):
    """ノード中心の正規化座標。frame 不正 or 画面外なら None。"""
    f = node.get("frame") or {}
    if not f:
        return None
    try:
        nx = (f["x"] + f["width"] / 2) / w
        ny = (f["y"] + f["height"] / 2) / h
    except (KeyError, ZeroDivisionError, TypeError):
        return None
    if 0 <= nx <= 1 and 0 <= ny <= 1:
        return nx, ny
    return None


def roots_and_size(ax):
    fr = ax[0].get("frame") or {}
    w, h = fr.get("width"), fr.get("height")
    if not w or not h:
        # 画面サイズ不明では全サブコマンドが座標を計算できない。データ異常として exit 2
        print("root 要素の frame が不正で画面サイズを特定できません", file=sys.stderr)
        sys.exit(2)
    return ax, w, h


def cmd_resolve(args):
    """`serve-sim --list -q` の JSON を stdin から受け、接続先を BASE / WS / UDID の
    3行で出力する。lib.sh sim_resolve から呼ばれる唯一の解決実装。"""
    try:
        d = json.load(sys.stdin)
    except Exception:
        return 1
    streams = parse_streams(d, args.want or "")
    if not streams:
        return 1
    if len(streams) > 1:
        # 複数候補のまま先頭を選ぶと別端末を誤操作しうるため、呼び出し側に明示指定させる
        print("接続先が一意に定まりません。device（機種名 / UDID）を指定してください", file=sys.stderr)
        return 2
    s = streams[0]
    print(http_base(s))
    print(s.get("wsUrl", ""))
    print(s.get("device", ""))
    return 0


def cmd_list(args, ax):
    roots, w, h = roots_and_size(ax)
    total = 0
    for r in roots:
        for n in walk(r):
            total += 1
            lbls = node_labels(n)
            if not lbls:
                continue
            c = norm_center(n, w, h)
            if not c:  # 画面外はタップ不可なので出さない
                continue
            print(f'{n.get("type",""):14} norm=({c[0]:.3f},{c[1]:.3f})  {" / ".join(lbls)!r}')
    if total >= AX_NODE_CAP:
        print(f"⚠️ AX が上限 {AX_NODE_CAP} 要素に達している。取りこぼしの可能性あり（スクショ併用）", file=sys.stderr)
    return 0


def cmd_anchor(args, ax):
    roots, w, h = roots_and_size(ax)
    labels = []
    for r in roots:
        for n in walk(r):
            if not norm_center(n, w, h):  # 画面外・frame 不正のラベルは在室判定に含めない
                continue
            labels.extend(node_labels(n))
    in_room = any(any(a in lbl for lbl in labels) for a in args.anchors)
    print("在室:", in_room)
    return 0 if in_room else 1


def cmd_label(args, ax):
    roots, w, h = roots_and_size(ax)
    target = args.text
    want_type = getattr(args, "type", None)
    exacts = []      # (nx, ny, node_type) 完全一致
    partials = []    # (nx, ny, matched_string) 部分一致（参考表示用）
    type_skipped = []  # 完全一致だが --type 不一致で除外したノードの type
    total = 0
    for r in roots:
        for n in walk(r):
            total += 1
            lbls = node_labels(n)
            c = norm_center(n, w, h)
            if not c:
                continue
            if target in lbls:
                if want_type and n.get("type") != want_type:
                    type_skipped.append(n.get("type", ""))
                    continue
                exacts.append((c[0], c[1], n.get("type", "")))
            else:
                for lbl in lbls:
                    if target in lbl:
                        partials.append((c[0], c[1], lbl))
                        break

    def report_not_found():
        # --type で全件除外された場合に「実在しない」と誤誘導しないよう、除外件数と実際の type を示す
        if type_skipped:
            print(f"完全一致 {len(type_skipped)}件はあるが --type {want_type} に一致しない"
                  f"（実際の type: {', '.join(sorted(set(type_skipped)))}）", file=sys.stderr)
        else:
            print(f"ラベルが見つかりません（完全一致）: {target!r}", file=sys.stderr)

    if getattr(args, "all", False):
        if not exacts:
            report_not_found()
            return 1
        for i, (nx, ny, t) in enumerate(exacts, 1):
            print(f"[{i}] {t:14} {nx:.4f} {ny:.4f}")
        return 0

    index = getattr(args, "index", None)
    if index is not None:
        if not (1 <= index <= len(exacts)):
            print(f"--index {index} が範囲外（完全一致 {len(exacts)}件）", file=sys.stderr)
            return 1
        nx, ny, _ = exacts[index - 1]
        print(f"{nx:.4f} {ny:.4f}")
        return 0

    if len(exacts) == 1:
        nx, ny, _ = exacts[0]
        print(f"{nx:.4f} {ny:.4f}")
        return 0

    if len(exacts) > 1:
        # 同名複数 → DFS 先頭を黙って選ぶと誤タップするため失敗にし、明示選択させる
        print(f"完全一致が {len(exacts)}件。--type <Type> か --index <N> で指定してください:", file=sys.stderr)
        for i, (nx, ny, t) in enumerate(exacts, 1):
            print(f"  [{i}] {t:14} {nx:.4f} {ny:.4f}", file=sys.stderr)
        return 1

    # 完全一致なし → 推測タップを避け失敗にする。候補は参考表示
    report_not_found()
    if partials:
        print("部分一致候補（自動タップしない。必要なら確認の上で座標指定）:", file=sys.stderr)
        for nx, ny, lbl in partials[:5]:
            print(f"  {nx:.4f} {ny:.4f}  {lbl!r}", file=sys.stderr)
    if total >= AX_NODE_CAP:
        print(f"⚠️ AX が上限 {AX_NODE_CAP} 要素に達している。取りこぼしの可能性あり（スクショ併用を推奨）", file=sys.stderr)
    return 1


def cmd_point(args, ax):
    _, w, h = roots_and_size(ax)
    nx = args.px / w
    ny = args.py / h
    if not (0 <= nx <= 1 and 0 <= ny <= 1):
        print(f"⚠️ 正規化結果が 0..1 外: ({nx:.4f},{ny:.4f})。画面外座標はタップ不可", file=sys.stderr)
        return 1
    print(f"{nx:.4f} {ny:.4f}")
    return 0


def main():
    # --base / --ax-file をサブコマンドの前後どちらでも受けられるよう、
    # main と各 subparser の両方に定義する。subparser 側は SUPPRESS 既定にして
    # 未指定時に main 側の値を上書きしないようにする（argparse の既定値上書き対策）。
    common = argparse.ArgumentParser(add_help=False)
    common.add_argument("--base", default=argparse.SUPPRESS,
                        help="serve-sim base URL（未指定は SIM_BASE → serve-sim --list から自動解決）")
    common.add_argument("--ax-file", default=argparse.SUPPRESS, help="AX を再取得せずファイルから読む")

    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--base")
    p.add_argument("--ax-file")
    sub = p.add_subparsers(dest="cmd", required=True)

    sub.add_parser("list", help="画面内要素の一覧", parents=[common])

    sa = sub.add_parser("anchor", help="在室判定", parents=[common])
    sa.add_argument("anchors", nargs="+")

    sl = sub.add_parser("label", help="ラベル→正規化座標", parents=[common])
    sl.add_argument("text")
    sl.add_argument("--type", help="要素タイプで絞る（例: Button / StaticText）")
    sl.add_argument("--index", type=int, help="完全一致が複数のとき N番目（1始まり）を選ぶ")
    sl.add_argument("--all", action="store_true", help="完全一致の全件を index/type/座標付きで表示")

    sp = sub.add_parser("point", help="AXポイント座標→正規化座標", parents=[common])
    sp.add_argument("px", type=float)
    sp.add_argument("py", type=float)

    sr = sub.add_parser("resolve", help="serve-sim --list -q の JSON(stdin)から接続先を解決")
    sr.add_argument("--want", default="", help="device（UDID 等）への部分一致で絞る")

    args = p.parse_args()
    if args.cmd == "resolve":
        return cmd_resolve(args)
    ax = load_ax(args)
    if not isinstance(ax, list) or not ax:
        # 正常な画面で AX が空になることはないため取得異常に寄せ、anchor の非在室(1)と区別する
        print("AX が空（取得異常の可能性）", file=sys.stderr)
        return 2
    return {"list": cmd_list, "anchor": cmd_anchor, "label": cmd_label, "point": cmd_point}[args.cmd](args, ax)


if __name__ == "__main__":
    sys.exit(main())

---
name: control-ios
description: iOS Simulator を起動・操作する。タップ・スワイプ・スクロール・スクリーンショット取得・テキスト入力・AXツリー参照など。画面確認や UI の操作、アプリの動作確認をエージェントで行う際に使用。simulator 操作、serve-sim、画面をタップ/スクロール、スクショ確認 などの言及時に使用。
---
`serve-sim` CLI と `xcrun simctl` で iOS Simulator を確認・操作するスキル。定型操作は `{THIS_SKILL_DIR}/scripts/`（接続先解決・座標変換・在室判定などを内包）で行う。

> 実行は動作確認済みの `serve-sim@0.1.44` に固定している（scripts は `lib.sh` の `SERVE_SIM_PKG`、生コマンドは `npx serve-sim@0.1.44` と明示）。latest 追従だと非公開挙動（長押し判定等）の変更でサイレントに壊れるため、バージョンを上げる際は動作確認とセットで行う。

## 前提

- macOS（Apple Silicon / arm64 のみ。serve-sim 同梱バイナリが arm64 限定で Intel Mac では動かない） / Xcode CLI / Node.js ≥18。1台だけ Booted の前提。複数台時は接続先を明示する。
- **座標系の使い分け**（混同に注意）:
  - スクリプト引数・スクショ目視は **正規化 0..1**（左上 `(0,0)`〜右下 `(1,1)`）を使うのが安全。
  - AX（`/ax`）は**論理ポイント**（iPhone 17 で 402×874）、`/config`・スクショは**ピクセル**（同 1206×2622 = 3倍）。`tap.sh --point` に渡すのは AX 論理ポイントで、スクショのピクセル座標ではない。
- **`-d`（接続先）の指定**: スクリプト（`ensure-sim.sh` / `tap.sh` 等）は機種名 / UDID どちらでもよい（`lib.sh` が解決。同名複数台は Booted 優先→OS 最新）。生 `npx serve-sim@0.1.44`（`button`/`type`/`gesture` 等）は**フル UDID 必須**（省略・部分指定だと `No serve-sim server running`）。UDID は `ensure-sim.sh` の出力（`SIM_UDID`）を使う。

## 起動・疎通確認

`{THIS_SKILL_DIR}/scripts/ensure-sim.sh [device]` で Booted 保証 → serve-sim アタッチまで冪等に行い `SIM_BASE=... SIM_WS=... SIM_UDID=...` を返す。**出力は eval + export して後続に引き継ぐ**と、スクリプトのたびに走る接続先解決（`npx`で毎回数秒）を省略できる。

```sh
eval "$({THIS_SKILL_DIR}/scripts/ensure-sim.sh "iPhone 17")" && export SIM_BASE SIM_WS SIM_UDID
curl -s "$SIM_BASE/foreground"  # {"pid":...,"bundleId":"<前面アプリ>"}
curl -s "$SIM_BASE/config"      # {"width":1206,"height":2622,"orientation":"portrait"}
```

- 疎通確認の URL はポート直打ち（`http://127.0.0.1:3100`）にしない。detach 構成では base が `http://127.0.0.1:3100/helper/<UDID>` になり、直打ちは `/ax` がハングする。必ず `ensure-sim.sh` が返す `SIM_BASE` を使う。

- **システム権限ダイアログ表示中は `/foreground` が `com.apple.springboard` を返す**。アプリが落ちたと誤認せず、「許可 / 許可しない」を `tap` で閉じれば前面はアプリに戻る。
- 複数台時はヘルパーが1台につき別ポート（1台目 `3100`、2台目 `3101`…）。新規 Simulator はアプリ未インストール・未ログインのことが多い（`xcrun simctl listapps <udid> | grep <bundle-id>` で確認）。

## 画面を見る（スクリーンショット）

`{THIS_SKILL_DIR}/scripts/screenshot.sh [出力先.png]`。省略時は一時ファイルに保存しパスを返す。

```sh
SS=$({THIS_SKILL_DIR}/scripts/screenshot.sh)
```

## 在室判定（どの画面にいるか）

`{THIS_SKILL_DIR}/scripts/anchor.sh "<label>" ["<label2>" …]`。渡したラベルが**現在画面内の要素ラベル**に**部分一致**すれば exit 0、無ければ exit 1（AX 取得異常は exit 2）。画面外・frame 不正の要素は判定に含めないため、スクロールで画面外に出たラベルはヒットしない。AX ラベルは複合文字列（例: `'お知らせ一覧、キャンペーン、未読12'`）で返ることがあるため部分一致で判定する。

```sh
{THIS_SKILL_DIR}/scripts/anchor.sh "利用履歴" "アカウント設定"
```

## 要素を探してタップ

基本はピクセル目視ではなく **AX ツリーの要素をラベルで指定**してタップする（座標解決・正規化はスクリプトが行う）。座標は機種・OS・レイアウトでズレるため、**座標直打ちはラベルが取れない時の最終手段**。

```sh
python3 {THIS_SKILL_DIR}/scripts/ax_tools.py list           # type / 正規化座標 / ラベルを一覧
{THIS_SKILL_DIR}/scripts/tap.sh --label "ホーム"            # ラベル解決してタップ（exact 一致）
{THIS_SKILL_DIR}/scripts/tap.sh --label "編集" --type Button   # 同名複数一致を要素タイプで絞る
{THIS_SKILL_DIR}/scripts/tap.sh --label "削除" --index 2     # 同名複数一致の N番目（1始まり）
{THIS_SKILL_DIR}/scripts/tap.sh --norm <nx> <ny>            # 正規化座標でタップ（スクショ目視時はこれ）
{THIS_SKILL_DIR}/scripts/tap.sh --point <px> <py>           # AX 論理ポイントでタップ
```

`list`・`anchor` とも `AXLabel` に加え `AXValue` / `AXPlaceholderValue` も拾う（プレースホルダ「キーワードで検索」等は `AXValue` で返るため）。
`ax_tools.py` の接続先は未指定なら `SIM_BASE` → `serve-sim --list` の順で自動解決される（detach 構成の helper パス付き base にも対応）。複数台時のみ `--base` か `SIM_BASE` の明示が必要。

注意:

- **ラベル未発見・画面外座標のときは tap せず exit 1**（推測タップしない）。部分一致候補は stderr に出る。
- **同名の完全一致が複数あるときも tap せず exit 1**（候補一覧を stderr に表示）。カテゴリ見出しと選択肢が同文言の画面等で誤爆しないため。`--type` / `--index` で明示するか、`python3 {THIS_SKILL_DIR}/scripts/ax_tools.py label "<text>" --all` で全件確認して選ぶ。
- **無効（グレーアウト）のボタンは AX に存在するが tap しても無反応**。スクショで淡色表示を疑い別経路へ。
- **AX は最大500要素まで**。上限到達画面（`list` が警告）はスクショ併用。**上限到達時はラベル未発見でも要素が無いとは限らない**（実在ボタンが取りこぼされる実測あり）。スクショ目視 + `--norm` にフォールバックする。

## ジェスチャー（スクロール・ドラッグ・戻る）

`{THIS_SKILL_DIR}/scripts/scroll.sh <up|down> [fast|slow] [short|long]`。up/down は**見たいコンテンツの方向**（`down`=ページを下へ）。既定は低速・慣性抑制、`short` で振り幅小。

```sh
{THIS_SKILL_DIR}/scripts/scroll.sh down          # 後続コンテンツを表示
{THIS_SKILL_DIR}/scripts/scroll.sh up short      # 少しだけ上へ戻す
```

任意のドラッグ（モーダルの下スワイプ dismiss 等）は `{THIS_SKILL_DIR}/scripts/drag.sh '<eventsJSON>' [delayMs]`:

```sh
{THIS_SKILL_DIR}/scripts/drag.sh '[{"type":"begin","x":0.5,"y":0.2},{"type":"move","x":0.5,"y":0.6},{"type":"end","x":0.5,"y":0.9}]'
```

注意:

- **単発タップは必ず `tap`**。`gesture` を begin/end で別呼び出しすると long-press 扱いになる（~100ms 超で長押し判定）。**長押し**はこの癖を利用する:

  ```sh
  npx serve-sim@0.1.44 gesture '{"type":"begin","x":0.4,"y":0.117}' -d "$SIM_UDID"; sleep 0.7
  npx serve-sim@0.1.44 gesture '{"type":"end","x":0.4,"y":0.117}' -d "$SIM_UDID"
  ```

- **「戻る」は左端スワイプでは不発**。ナビバーの戻るボタンを `tap`（隠れていれば先に `scroll.sh up`）。戻るボタンは AX にラベルが無いことがあり、その場合は左上（おおよそ `tap.sh --norm 0.05 0.075`）を tap（最終手段）。
- **モーダルシートは下スワイプで閉じる**。上端に戻るボタンが無く戻れないときはシートを疑い `drag.sh` で上→下にドラッグして dismiss。
- **スクロール後は約2秒 settle 待ち**してから要素を取り直す（慣性継続中だと別要素を踏む）。

## ハードウェアボタン

`npx serve-sim@0.1.44 button <name> -d "$SIM_UDID"`。有効な `<name>` は次の6つのみ:

| name | 効果 |
|---|---|
| `home` | ホームボタン1回 |
| `swipe_home` | 下端から上スワイプでホームへ（Face ID 機の実機相当） |
| `app_switcher` | ホーム2回押し（アプリスイッチャー） |
| `lock` | ロック / スリープ |
| `siri` | サイドボタン長押しで Siri |
| `side_button` | サイドボタン1回 |

## テキスト入力

日本語・正確な文字列は `{THIS_SKILL_DIR}/scripts/type-paste.sh "<文字列>" --label "<入力欄ラベル>"`（または `--norm <nx> <ny>`）。pbcopy → フォーカス → 長押し → 「ペースト」tap まで自動化する。

```sh
{THIS_SKILL_DIR}/scripts/type-paste.sh "東京" --label "キーワードで検索"
```

- 入力欄の座標は**目視推定しない**。プレースホルダー付き欄は `python3 {THIS_SKILL_DIR}/scripts/ax_tools.py label "<プレースホルダー文言>"` で正確な座標を取得してから `--norm` に渡す（目視座標のズレでペーストメニューが出ず失敗しやすい）。ラベルで直接指定できるならそれが最善。
- ASCII のみなら `npx serve-sim@0.1.44 type "hello" -d "$SIM_UDID"` も可。ただし **US 物理キーボード固定**でかな IME 下では崩れる（`"Ramen"` → `"らめn"`）ため日本語には使わない。
- 既存テキストのクリアは入力欄右端の「✕」（AX ラベル `textFieldClearButton`）を tap が早い。

## タブ巡回

タブバーの各タブは `RadioButton` として AX に出る（ラベル＝タブ名）。座標は機種で変わるので `{THIS_SKILL_DIR}/scripts/tap.sh --label "<タブ名>"` で解決してタップ。`RadioButton` の並びはタブバー有無判定にも使える。

## 標準作業ループ

1. `eval "$({THIS_SKILL_DIR}/scripts/ensure-sim.sh)" && export SIM_BASE SIM_WS SIM_UDID` … Booted + serve-sim 起動保証（export で後続の接続先解決を省略）
2. `{THIS_SKILL_DIR}/scripts/anchor.sh "<anchor>" …` … 対象画面に居るか在室判定
3. `python3 {THIS_SKILL_DIR}/scripts/ax_tools.py list` … 操作対象の要素・座標を確認
4. `{THIS_SKILL_DIR}/scripts/tap.sh --label "<ラベル>"` … タップ（未発見なら推測せず報告）
5. `{THIS_SKILL_DIR}/scripts/screenshot.sh` … 結果を確認
6. 遷移しない時 … 戻るは「戻るボタン tap」、スクロールは `{THIS_SKILL_DIR}/scripts/scroll.sh`
7. 日本語入力 … `{THIS_SKILL_DIR}/scripts/type-paste.sh "<文字列>" --label "<入力欄>"`

## 後始末

起動維持を望まれる場合を除き終了後に止める（残るとポート `3100` を専有し次回起動を妨げる）:

```sh
npx serve-sim@0.1.44 --kill     # 全停止（特定の1台は --kill "<device>"）
```

## 参考リファレンス（必要時のみ）

- 権限ダイアログの事前付与/拒否: <{THIS_SKILL_DIR}/references/permission.md>
- カメラ注入 / アプリ権限 / 回転 / CoreAnimation / pinch・edge / 全エンドポイント: serve-sim 公式 references（<https://github.com/EvanBacon/serve-sim/tree/main/skills/serve-sim/references>）

## 権限ダイアログの事前付与/拒否

serve-sim は通知許可などパーミッションの事前付与/拒否ができる。

```
npx serve-sim@0.1.44 permissions grant  <permission> <bundle-id>
npx serve-sim@0.1.44 permissions revoke <permission> <bundle-id>
npx serve-sim@0.1.44 permissions reset  <permission|all> <bundle-id>
npx serve-sim@0.1.44 permissions list   [bundle-id]
```

```sh
BUNDLE={アプリのBundle ID}

# 通知ダイアログを出さない（事前に許可）
npx serve-sim@0.1.44 permissions grant notifications "$BUNDLE"
# 写真ライブラリ（画像アップロード等の確認時）
npx serve-sim@0.1.44 permissions grant photos "$BUNDLE"
# 現在の状態を確認
npx serve-sim@0.1.44 permissions list "$BUNDLE"
# 再プロンプトさせたい時はリセット
npx serve-sim@0.1.44 permissions reset all "$BUNDLE"
```

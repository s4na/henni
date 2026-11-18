# 変異（henni）

henniは、Rubyの比較式を一か所ずつ書き換えてRSpecを実行し、テストがその変更を検出できるかを調べるツールです。CRuby 3.4／4.0とPrism 2.x（2.1以降）を使います。

## サンプルを試す

リポジトリのルートで依存gemをインストールし、同梱のサンプルへ移動します。

```sh
bundle install
cd examples/boundary
BUNDLE_GEMFILE=../../Gemfile bundle exec henni run lib/discount.rb
```

サンプルでは `price >= 1_000` を `price > 1_000` に変異させます。既存のテストは1,001円だけを確認するため、結果は `survived`、終了コードは1です。`spec/discount_spec.rb` の `RSpec.describe` 内に次のテストを追加し、同じコマンドを実行すると `killed`、終了コード0になります。

```ruby
it "ちょうど1,000円でも適用する" do
  expect(Discount.eligible?(1_000)).to be(true)
end
```

## 自分のRubyプロジェクトで使う

Gemfileのtestグループに取得したhenniの絶対パスを指定し、`bundle install` 後にプロジェクトのルートから起動します。対象ファイルをプロジェクト相対パスで一つ指定してください。

```ruby
gem "henni", path: "/absolute/path/to/henni", group: :test
```

```sh
bundle exec henni run --timeout 30 lib/discount.rb > henni-result.json
```

- メソッド本体にある `>=`／`>`、`<=`／`<`、`==`／`!=` を対になる演算子へ置換し、生成したソースを再解析します。
- プロジェクトを一時ディレクトリにコピーし、元コードのbaselineと各変異をそれぞれ新しいコピー、新しいRubyプロセスで実行します。RSpecは `spec/` を固定seedで実行し、対象ファイルの `require`／`require_relative` と実行したexampleを照合します。
- 標準出力はJSON、RSpecのログは標準エラー出力です。終了コードは0が全変異を検出または対象なし、1が生き残りあり、2がbaseline失敗・実行障害・時間切れなどの判定不能、130が割込みです。既定の制限時間は各RSpecプロセス60秒です。

`.git`、`.bundle`、`vendor/bundle`、`henni-report` はコピー対象から除きます。コピー対象にsymlinkや特殊ファイルがある場合は停止します。プロジェクト直下のGemfileで起動した場合、lockfileもプロジェクト内に置いてください。テストはコピー内のソースとlockfileを読み込み、依存gemはインストール済みのものを使います。

## Railsでの検証範囲

Ruby 3.4／4.0の両方で、Rails 8.1・rspec-rails 8.1・SQLiteを使うアプリからCLIを起動するE2Eテストを実行します。request specはJSONの値を確認し、system specはheadless Chromeでボタンを押し、JavaScriptが同じAPIから取得した割引結果を画面で確認します。gem側のテストでは、価格の境界を変えると両方のspecが失敗し、在庫の未検証の境界を変えると両方が通ることをJSONから検証します。

リポジトリのルートで `bundle install` 後、Chromeが利用できる環境で実行してください。

```sh
bundle exec rspec                        # gemのテスト全体
bundle exec rspec spec/rails_e2e_spec.rb  # Rails E2Eのみ
```

検証したDB構成は、各作業コピー内のSQLiteファイルです。PostgreSQLやRedisなどの外部サービスを使う場合は、テスト環境側で状態を隔離する必要があります。

## 設計

- [本体の設計](docs/design.md): Prismでの変異生成、RSpec／Minitest、Railsの状態隔離、判定、差分実行、キャッシュ、実装順序、ライセンス方針。
- [GitHub Actionsの設計](docs/ci.md): ツール自体のCI、自己ミューテーション、利用先Railsアプリへの組込み。

## 参考元とライセンス方針

[mizchi/mutator](https://github.com/mizchi/mutator)の、ASTと元ソースの範囲による変異、変異計画とテストランナーの分離、差分実行と結果再利用の考え方を参考にします。

henniの自作部分は[MITライセンス](LICENSE)です。コードや文章を再利用する場合は、元の著作権表示・ライセンスを保持し、参照したcommitとファイルを記録します。具体的な扱いは[本体設計のライセンス方針](docs/design.md#13-参考元とライセンス)に定めます。

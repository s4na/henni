# 変異（henni）

henniは、Rubyの比較式を一か所ずつ書き換えてRSpecとMinitestを実行し、テストがその変更を検出できるかを調べるツールです。CRuby 3.4／4.0とPrism 2.x（2.1以降）を使います。

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
- プロジェクトを一時ディレクトリにコピーし、元コードのbaselineと各変異をそれぞれ新しいコピー、新しいRubyプロセスで実行します。フレームワークごとに固定seedで実行し、対象ファイルのロード、実行予定の全テストID、実際に完了したIDを照合します。
- 標準出力はJSON、テストのログは標準エラー出力です。終了コードは0が全変異を検出または対象なし、1が生き残りあり、2がbaseline失敗・実行障害・時間切れなどの判定不能、130が割込みです。既定の制限時間は各テストプロセス60秒です。

`.git`、`.bundle`、`vendor/bundle`、`henni-report` はコピー対象から除きます。プロジェクト内のsymlinkは各作業コピー内の参照先に張り直し、ソケットとFIFOは警告してコピーを省きます。外部へのリンクや参照先が存在しないリンクは入力エラーです。各プロセスに独立したフルコピーを作るため、依存や生成物が大きいプロジェクトではディスク使用量とコピー時間が増えます。プロジェクト直下のGemfileで起動した場合、lockfileもプロジェクト内に置いてください。テストはコピー内のソースとlockfileを読み込み、依存gemはインストール済みのものを使います。

## 実行するテスト

既定の `--runner auto` は `spec/` または `.rspec` のあるプロジェクトでRSpecを起動し、`test/` 以下に `*_test.rb` または `test_*.rb` があればMinitestも起動します。`test_helper.rb` は通常のヘルパーとしてテストから読み込みます。RSpecは自身の設定でファイルを発見します。Minitestはサブディレクトリを再帰的に探索し、`Minitest::Test` とspec DSLの両方を実行します。Railsのsystem testも対象です。

両方があるアプリでは、元コードと各変異についてRSpecとMinitestを別々の作業コピーで実行します。少なくとも一方が対象をロードし、全スイートが予定したテストを完走すると判定できます。一方が変異を検出しても、他方に実行エラー・skip・欠落・timeoutがあれば全体は判定不能です。JSONの `runners` と `suites` で実行したフレームワークとその結果を確認できます。

```sh
bundle exec henni run --runner both app/models/offer.rb
bundle exec henni run --runner minitest lib/discount.rb
bundle exec henni run --rspec-pattern 'checks/**/*_spec.rb' --minitest-pattern 'checks/**/*_test.rb' lib/discount.rb
```

`--runner both` は両方のスイートを必須にします。独自の配置・命名では、プロジェクト相対のglobを引用符で囲んで指定してください。

## Railsでの検証範囲

同じRails 8.1＋SQLiteアプリで、次のテストをbaselineと各変異で実際に起動し、gem側のE2Eテストが各テストのIDを照合します。

| フレームワーク | CIが実行するテスト |
|---|---|
| RSpec Rails | model、controller、request、routing、view、helper、feature、system、job、mailer、mailbox、channel、generator、独自のservice spec |
| Minitest | model、controller、integration、routing、view、helper、system、job、mailer、mailbox、channel、connection、generator、独自ディレクトリのspec DSL |

両フレームワークのsystemテストはheadless Chromeを操作します。価格の境界を変えると、それぞれのmodel・controller・HTTP・systemテストが失敗します。在庫の未検証の境界を変えると両スイートが通り、同じrunで `killed` と `survived` が1件ずつ記録されます。CIはRuby 3.4／4.0とMinitest 6.1、Ruby 3.4とMinitest 5.25.4で検証します。

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

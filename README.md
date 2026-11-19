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

アプリで使用するテストフレームワーク（RSpec、Minitest、または両方）とともに、GemfileのtestグループにGitHubリポジトリを指定します。

```ruby
gem "henni", github: "s4na/henni", branch: "main", group: :test
```

```sh
bundle install
bundle exec henni run --timeout 30 lib/discount.rb > henni-result.json
```

`Gemfile.lock` が取得したリビジョンを固定します。mainの更新を取り込むには `bundle update henni` を実行してください。mainへのpushごとにGitHub Actionsが専用ワークフローの実行番号をパッチ番号に使い、元のコミットSHAを記録したコミットをmainに追加します。利用中のバージョンと元のSHAは次のコマンドで確認できます。

```sh
bundle exec ruby -e 's = Gem.loaded_specs.fetch("henni"); puts s.version, s.metadata.fetch("source_revision")'
```

- メソッド本体にある `>=`／`>`、`<=`／`<`、`==`／`!=` を対になる演算子へ置換し、生成したソースを再解析します。
- プロジェクトを一時ディレクトリにコピーし、元コードのbaselineと各変異をそれぞれ新しいコピー、新しいRubyプロセスで実行します。フレームワークごとに固定seedで実行し、対象ファイルのロード、実行予定の全テストID、実際に完了したIDを照合します。
- 標準出力はJSON、テストのログは標準エラー出力です。変異をすべて検出した場合は終了コード0、1件でも生き残った場合は1です。生成できる変異が0件のときは、テストを起動せず JSON に `no_mutations: true` を記録します。この場合の終了コードは既定で0、`--fail-on-empty` 指定時は1です。変異がある場合は `no_mutations: false` です。終了コード2がbaseline失敗・実行障害・時間切れなどの判定不能、130が割込みです。baselineの制限時間は既定60秒です。変異の制限時間はスイートごとに `min(--timeout, max(1秒, baseline所要時間 × 5))` とし、`--timeout` を上限として使います。時間切れは引き続き `timeout`・判定不能であり、`killed` には数えません。

`.git`、`.bundle`、`vendor/bundle`、`henni-report` はコピー対象から除きます。プロジェクト内のsymlinkは各作業コピー内の参照先に張り直し、ソケットとFIFOは警告してコピーを省きます。外部へのリンクや参照先が存在しないリンクは入力エラーです。各プロセスに独立したフルコピーを作るため、依存や生成物が大きいプロジェクトではディスク使用量とコピー時間が増えます。プロジェクト内のGemfile（サブディレクトリを含む）で起動した場合、lockfileもプロジェクト内に置いてください。テストはコピー内のソースとlockfileを読み込み、依存gemはインストール済みのものを使います。

レポートの `scope` は `Store::Sale#eligible?` のような修飾名です。`method` には従来どおりメソッド名だけが入ります。変異 ID はメソッド本体からの構造位置を使うので、無関係なメソッドの追加や並べ替えでは変わりません。同じメソッド名の再定義はソース内の出現順で区別します。従来方式で生成した ID とは一致しません。

## 等価変異を除外する

テストで区別できない理由を確認した変異は、プロジェクト直下の `.henni-ignore.json` に登録できます。JSONレポートの `path`、`id`、`scope_fingerprint` をコピーし、判断の理由を `reason` に書きます。

```json
[
  {
    "path": "lib/discount.rb",
    "id": "<レポートのid>",
    "scope_fingerprint": "<レポートのscope_fingerprint>",
    "reason": "入力仕様により境界値を受け付けない"
  }
]
```

一致した変異は実行を省き、`counts.ignored` に集計します。全件が除外されていても元のスイートの成功を確認します。メソッドの内容が変わった登録や、対象ファイルから消えた変異の登録は `stale_ignores` に載ります。現存する変異は通常どおり実行されるので、理由が今も当てはまるか確認してから登録を更新してください。

## 実行するテスト

既定の `--runner auto` は `spec/` または `.rspec` のあるプロジェクトでRSpecを起動し、`test/` 以下に `*_test.rb` または `test_*.rb` があればMinitestも起動します。`test_helper.rb` は通常のヘルパーとしてテストから読み込みます。RSpecは自身の設定でファイルを発見します。Minitestはサブディレクトリを再帰的に探索し、`Minitest::Test` とspec DSLの両方を実行します。Railsのsystem testも対象です。

両方があるアプリでは、元コードと各変異についてRSpecとMinitestを別々の作業コピーで実行します。少なくとも一方が対象をロードし、全スイートが予定したテストを完走すると判定できます。一方が変異を検出しても、他方に実行エラー・skip・欠落・timeoutがあれば全体は判定不能です。JSONの `runners` と `suites` で実行したフレームワークとその結果を確認できます。

```sh
bundle exec henni run --runner both app/models/offer.rb
bundle exec henni run --runner minitest lib/discount.rb
bundle exec henni run --rspec-pattern 'checks/**/*_spec.rb' --minitest-pattern 'checks/**/*_test.rb' lib/discount.rb
```

`--runner both` は両方のスイートを必須にします。独自の配置・命名では、プロジェクト相対のglobを引用符で囲んで指定してください。

JSONの各 `suites` に `duration_seconds`（子プロセス起動から終了処理まで）、`timeout_seconds`、`timeout_source` を記録します。計測済みの成功baselineから変異の制限を算出した場合は `baseline_duration_seconds` も記録します。計測値が無効・未取得なら設定値を使い、`timeout_source` は `configured` とします。コピー時間は含みません。変異の時間切れは `reason` でbaseline通過後の実行であることを示しますが、変異が原因と断定するものではありません。負荷変動による時間切れも判定不能のまま扱います。

## 例外による変異検出

変異後のテストでassertionが失敗した場合、または `NoMethodError`、`TypeError`、`ArgumentError`、`NameError`、`IndexError`、`KeyError`、`RangeError`、`ZeroDivisionError`、`FrozenError` が起きた場合は、同じsnapshotの元コードで同じスイートをもう一度実行します。対象のロード・digest・全テストIDが一致し、元コードが再度成功したときだけ assertionの失敗を `killed_by: "assertion"`、例外を `killed_by: "exception"` と判定します。再確認は元コードの実行なので、制限時間には `--timeout` の設定値を使います。再確認の結果はスイートの `baseline_recheck` に残ります。

起動・suiteの失敗、未完了のテスト、`IOError`・`Errno::*`・DB接続エラーなど、上記以外の例外は引き続き判定不能です。再確認は一度だけなので、非決定的なテストの安定性を保証するものではありません。

## Railsでの検証範囲

同じRails 8.1＋SQLiteアプリで、次のテストをbaselineと各変異で実際に起動し、gem側のE2Eテストが各テストのIDを照合します。

| フレームワーク | CIが実行するテスト |
|---|---|
| RSpec Rails | model、controller、request、routing、view、helper、feature、system、job、mailer、mailbox、channel、generator、独自のservice spec |
| Minitest | model、controller、integration、routing、view、helper、system、job、mailer、mailbox、channel、connection、generator、独自ディレクトリのspec DSL |

両フレームワークのsystemテストはheadless Chromeを操作します。価格の境界を変えると、それぞれのmodel・controller・HTTP・systemテストが失敗します。在庫の未検証の境界を変えると両スイートが通り、同じrunで `killed` と `survived` が1件ずつ記録されます。CIはRuby 3.4／4.0とMinitest 6.1、Ruby 3.4とMinitest 5.25.4で検証します。

HTTPリクエストを通じた変異検出は、DBを使わない小さな見積もりAPIでも検証します。RSpecが割引開始の10個、Minitestが注文上限の50個を担当し、片方だけなら2件中1件、両方なら2件とも変異を検出します。フォームとJSONでの正常な注文、入力エラー、非対応のHTTPメソッド、Railsの起動失敗もテストします。アプリとルートを1ファイルに収める構成は、[Rails公式のAction Controller再現テンプレート](https://github.com/rails/rails/blob/main/guides/bug_report_templates/action_controller.rb)を参考にしました。

リポジトリのルートで `bundle install` 後に実行してください。SQLiteアプリのsystemテストにはChromeを使います。

```sh
bundle exec rspec                        # gemのテスト全体
bundle exec rspec spec/rails_e2e_spec.rb  # SQLiteとChromeを使うRails E2E
bundle exec rspec spec/controller_app_spec.rb  # 見積もりAPIのE2E（DB・Chrome不要）
```

検証したDB構成は、各作業コピー内のSQLiteファイルです。PostgreSQLやRedisなどの外部サービスを使う場合は、テスト環境側で状態を隔離する必要があります。

## 設計

- [本体の設計](docs/design.md): Prismでの変異生成、RSpec／Minitest、Railsの状態隔離、判定、差分実行、キャッシュ、実装順序、ライセンス方針。
- [GitHub Actionsの設計](docs/ci.md): ツール自体のCI、自己ミューテーション、利用先Railsアプリへの組込み。

## 参考元とライセンス方針

[mizchi/mutator](https://github.com/mizchi/mutator)の、ASTと元ソースの範囲による変異、変異計画とテストランナーの分離、差分実行と結果再利用の考え方を参考にします。

henniの自作部分は[MITライセンス](LICENSE)です。コードや文章を再利用する場合は、元の著作権表示・ライセンスを保持し、参照したcommitとファイルを記録します。具体的な扱いは[本体設計のライセンス方針](docs/design.md#13-参考元とライセンス)に定めます。

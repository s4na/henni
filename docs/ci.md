# GitHub Actionsの設計

状態: [実装済みのCI](../.github/workflows/ci.yml)はRuby 3.4／4.0でgemのRSpec、Rails 8.1のRSpec・Minitest全スイート（両方のheadless Chromeテストを含む）を使うE2E、gem buildを実行します。actionlintとzizmorでworkflowを、RuboCopのLintでRubyコードを検査します。以下は今後のジョブを含む設計例です。

判定、隔離、差分、キャッシュの契約は[本体設計](design.md)を参照する。

## 1. ツール自体のCI

初期の対応表を小さく保ち、正式対応を宣言する組合せは必須CIで検証する。

| ジョブ | 対象 | 契機・役割 |
|---|---|---|
| core | Ruby 3.4 / 4.0、Prism 2.1.0と最新2.x | PR / main。解析、変異生成、判定、CLI |
| adapter | RSpec / Minitestの対応版 | PR / main。discovery・選択・失敗・終了契約 |
| rails | Ruby 3.4 / 4.0 × Rails 8.1。RSpec版とMinitest版の小さいfixture | PR / main。autoload、DB隔離、callback呼出し等 |
| packaging | 最新安定Ruby | PR / main。gem build、同梱ファイル、ライセンス |
| self-mutation | 最新安定Rubyで変更範囲 | PR。ツール自身のテストを検証 |
| mutation-full | 設定対象全体 | 週次 / 手動。差分実行が対象外にした箇所を検証 |
| compatibility | Ruby head、Rails edge、Prism次期版候補 | 週次 / 手動。非blockingの先行検知 |
| platform | macOSでprocess・パス・終了処理 | 少数のPRジョブまたは週次。正式対応前に必須化 |

coreの全組合せとRailsの全組合せを無条件に掛け合わせない。最小Prism版はcoreで確認し、Railsは主に固定lockfileで動かす。RSpec / Minitestの下限・上限は、実装時に対応APIを確認し、lockfile付きfixtureで確定する。

以下はRake taskを導入する段階のcore workflow案である。Prism最小版、Rails fixture、macOSのジョブは上の表に従って追加する。

```yaml
name: CI

on:
  pull_request:
  push:
    branches: [main]

permissions:
  contents: read

concurrency:
  group: ci-${{ github.workflow }}-${{ github.event.pull_request.number || github.ref }}
  cancel-in-progress: true

jobs:
  core:
    runs-on: ubuntu-latest
    timeout-minutes: 15
    strategy:
      fail-fast: false
      matrix:
        ruby: ["3.4", "4.0"]
    steps:
      - uses: actions/checkout@v7
        with:
          persist-credentials: false
      - uses: ruby/setup-ruby@v1
        with:
          ruby-version: ${{ matrix.ruby }}
          bundler-cache: true
      - run: bundle exec rake test
      - run: bundle exec rake lint

  packaging:
    runs-on: ubuntu-latest
    timeout-minutes: 10
    steps:
      - uses: actions/checkout@v7
        with:
          persist-credentials: false
      - uses: ruby/setup-ruby@v1
        with:
          ruby-version: "4.0"
          bundler-cache: true
      - run: bundle exec rake package:verify
```

以下の各例では、読みやすさのためActionのメジャー名を記載する。リポジトリへ入れる実装時には、確認したリリースのfull commit SHAへ固定し、Dependabotで更新する。Rubyのmatrixは系列指定で最新パッチを取得し、結果には実際の完全なバージョンを記録する。[^actions]

## 2. 自己ミューテーションのworkflow例

次は本ツール自身のRubyコードを検証する提案である。ツール本体、設定、runner adapter、複数workerの資源隔離が完成してから動く。段階2の自己適用は `--jobs 1` から始める。自己テストのrunnerには、実際に採用したものを設定する。

```yaml
name: Mutation

on:
  pull_request:
  schedule:
    - cron: "17 18 * * 0" # 月曜日 03:17 JST（UTCで記述）
  workflow_dispatch:

permissions:
  contents: read

concurrency:
  group: mutation-${{ github.workflow }}-${{ github.event.pull_request.number || github.ref }}
  cancel-in-progress: ${{ github.event_name == 'pull_request' }}

jobs:
  mutation:
    runs-on: ubuntu-latest
    timeout-minutes: 30
    env:
      MUTATION_BASE_SHA: ${{ github.event.pull_request.base.sha }}
    steps:
      - uses: actions/checkout@v7
        with:
          ref: ${{ github.event.pull_request.head.sha || github.sha }}
          fetch-depth: 0
          persist-credentials: false

      - uses: ruby/setup-ruby@v1
        with:
          ruby-version: "4.0"
          bundler-cache: true

      - name: Run mutation tests
        shell: bash
        run: |
          set -euo pipefail
          args=(run --ci --jobs 2 --time-budget 1200 --report-dir henni-report)
          if [[ "$GITHUB_EVENT_NAME" == "pull_request" ]]; then
            args+=(--since "$MUTATION_BASE_SHA")
          fi
          bundle exec henni "${args[@]}"

      - name: Write summary
        if: always()
        shell: bash
        run: |
          if [[ -f henni-report/summary.md ]]; then
            cat henni-report/summary.md >> "$GITHUB_STEP_SUMMARY"
          fi

      - name: Upload report
        if: always()
        uses: actions/upload-artifact@v7
        with:
          name: mutation-${{ github.run_id }}-${{ github.run_attempt }}
          path: henni-report/
          if-no-files-found: warn
```

ツール側の予算20分、GHA側の期限30分は初期例である。ツール側の予算にはbaselineも含め、レポートを書く余裕をGHA期限まで残す。強制キャンセル時のartifact保存は保証しない。

schemaが安定するまでは、GHA間でミューテーション結果を共有しない。最初から使うキャッシュは `ruby/setup-ruby` の `bundler-cache: true` による依存gemキャッシュである。[^actions] 結果再利用を追加するときは、[本体設計8節](design.md#8-prの差分テスト変更キャッシュ)のfingerprint検証をCLI自身が行う。

## 3. 利用先Railsアプリへの組込み

利用先では同じCLIを、そのアプリのbundleとRubyで起動する。workflowのRubyを無条件に4.0へ変更せず、アプリ側の実行環境に合わせる。

1. 通常のRailsテストCIを通す。
2. ミューテーション用にtest DBと実行資源を用意する。
3. アダプターが同じ隔離環境でbaselineを実行する。
4. PR headとbaseのmerge-baseから対象を選び、変異を実行する。
5. SummaryとJSONを保存し、未検出・未完了を品質ゲートへ反映する。

並列化時は[本体設計5節](design.md#5-実行方式とrailsの隔離)のworker別DB等のsetup hookを必須にする。全workerが同じtest DBを使う `--jobs 2` の設定をサンプルとして配布しない。アプリが利用するrunnerとDBに合わせたサンプルを、対応fixtureの完成後に用意する。

PR更新で古い実行を停止し、週次の全体実行はPR更新に巻き込まれないconcurrency groupにする。PRのレポートは「変更範囲のスコア」と明示し、全体の品質と取り違えない。

## 4. OSSのPRで必要な権限

テスト対象のPRコードを実行するworkflowは `pull_request` とし、`contents: read`、secret不要のfixtureで成立させる。`pull_request_target` で権限付きのままPR headを実行する構成は避ける。[^events]

最初はPRコメント投稿を必要とせず、Job Summaryとartifactで結果を返す。後続の権限付きjobで、PRが生成したartifactをコードとして実行しない。

## 導入を完了したと判断する条件

- 通常のテスト・adapter契約・packagingが、宣言したRubyの組合せで通る。
- PRではhead SHAを検証し、base／merge-baseが欠けると明示的に失敗する。
- surviving mutationと、baseline失敗・timeout・未完了を別の理由でCIへ返す。
- レポートに実際のRuby・Prismの版、head／base／merge-base、対象範囲、完了状態が残る。
- Railsの並列jobを有効にする前に、worker間と変異間のDB・cache・tmpの分離をfixtureで確認する。
- 週次の全体実行とPRの差分実行を、同じ「全体スコア」として表示しない。

## 参照資料

[^actions]: [actions/checkout](https://github.com/actions/checkout) / [ruby/setup-ruby](https://github.com/ruby/setup-ruby) / [actions/upload-artifact](https://github.com/actions/upload-artifact) / [workflow構文](https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax)

[^events]: [workflowイベント](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows) / [pull_request_targetの権限境界](https://docs.github.com/en/actions/reference/security/securely-using-pull_request_target)

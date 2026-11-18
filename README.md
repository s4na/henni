# 変異（henni）

Ruby／Rails向けのミューテーションテストツールを開発するプロジェクトです。コードへ小さな変更を加え、既存のテストがその変更を検出できるかを調べます。

**現在は設計段階です。gem、CLI、CI workflowは未実装です。**

## 設計

- [本体の設計](docs/design.md): Prismでの変異生成、RSpec／Minitest、Railsの状態隔離、判定、差分実行、キャッシュ、実装順序、ライセンス方針。
- [GitHub Actionsの設計](docs/ci.md): ツール自体のCI、自己ミューテーション、利用先Railsアプリへの組込み。

初期の対応目標はCRuby 3.4／4.0、Prism 2.1以降の2.x、Rails 8.1です。まずRuby＋RSpecで一つの変異を生成・実行・判定するところから始め、Rails、Minitest、PR差分実行へ広げます。対応を宣言する組合せは、実装時のfixtureとCIで検証します。

## 参考元とライセンス方針

[mizchi/mutator](https://github.com/mizchi/mutator)の、ASTと元ソースの範囲による変異、変異計画とテストランナーの分離、差分実行と結果再利用の考え方を参考にします。

henniの自作部分はMITを採用する方針です。コードや文章を再利用する場合は、元の著作権表示・ライセンスを保持し、参照したcommitとファイルを記録します。具体的な扱いは[本体設計のライセンス方針](docs/design.md#13-参考元とライセンス)に定めます。

# JobNet
スクリプトの呼び出し先やインプット/アウトプット内容を調べてドキュメントを生成するperlスクリプト

## バッチジョブフロー解析ツール

## 概要

バッチジョブの呼び出し階層を解析し、フロー図やCSV、JSON形式で出力するツールです。
サーバ老朽更新後の統合テスト支援を目的としています。

## 必要環境

- Perl 5.32.1 以上
- 標準モジュールのみ使用（CPAN不要）

## インストール

インストール不要です。リポジトリをクローンしてすぐに使用できます。

```bash
git clone <repository-url>
cd batch-flow-analyzer
```

## 使用方法

### 基本的な使い方

```bash
perl analyzer.pl --input /path/to/file_list.txt --output /path/to/output/
```

### オプション

| オプション | 説明 | デフォルト |
|-----------|------|-----------|
| `--input` | 起点スクリプトのリストファイル（必須） | - |
| `--output` | 出力ディレクトリ（必須） | - |
| `--max-depth` | 最大解析深度 | 10 |
| `--encoding` | ファイルエンコーディング | utf-8 |
| `--env` | 環境変数を指定（複数回指定可能） | - |
| `--env-file` | 環境変数定義ファイルのパス | - |

### 入力ファイルの形式

`file_list.txt` には起点となるスクリプトのフルパスを1行1ファイルで記述します。

```text
/opt/batch/daily/backup.sh
/opt/batch/daily/sync.sh
/usr/local/cobol/BATCH001.cbl
```

コメント行（`#`で始まる行）と空行は無視されます。

## 出力ファイル

解析結果は以下の7種類のファイルとして出力されます：

| ファイル | 形式 | 内容 |
|----------|------|------|
| `flowchart.md` | Mermaid | 呼び出し階層フロー図 |
| `dependencies.json` | JSON | 依存関係（機械処理用） |
| `dependencies.csv` | CSV | 依存関係（確認用） |
| `file_io.csv` | CSV | ファイル入出力一覧 |
| `db_operations.csv` | CSV | DB操作一覧 |
| `analysis.log` | テキスト | 解析ログ・警告 |
| `summary.txt` | テキスト | 統計サマリー |

## 対応言語

| 言語 | 呼び出し | ファイルI/O | DB操作 |
|------|---------|-------------|--------|
| sh/bash | ✅ | ✅ | ⚠️（sqlplus経由） |
| csh/tcsh | ✅ | ✅ | ⚠️（sqlplus経由） |
| COBOL | ✅ | ✅ | ✅ |
| PL/SQL | ✅ | ⚠️ | ✅ |

## 実行例

```bash
# 基本実行
perl analyzer.pl --input /opt/batch/file_list.txt --output /tmp/analysis_result/

# 深度を20階層まで解析
perl analyzer.pl \
  --input /opt/batch/file_list.txt \
  --output /tmp/analysis_result/ \
  --max-depth 20

# Shift-JISエンコーディングのファイルを解析
perl analyzer.pl \
  --input /opt/batch/file_list.txt \
  --output /tmp/analysis_result/ \
  --encoding shift-jis

# 環境変数を指定して変数展開を有効にする
perl analyzer.pl \
  --input /opt/batch/file_list.txt \
  --output /tmp/analysis_result/ \
  --env "BATCH_HOME=/opt/batch" \
  --env "SCRIPT_DIR=/home/app/scripts"

# 環境変数定義ファイルを使用
perl analyzer.pl \
  --input /opt/batch/file_list.txt \
  --output /tmp/analysis_result/ \
  --env-file /path/to/env_mapping.txt
```

### 環境変数定義ファイルの形式

`--env-file` オプションで指定するファイルは、以下の形式で記述します：

```text
# env_mapping.txt
BATCH_HOME=/opt/batch
SCRIPT_DIR=/home/app/scripts
APP_ROOT=/usr/local/app
LOG_DIR=/var/log/batch
```

コメント行（`#`で始まる行）と空行は無視されます。

## モジュール構成

```
batch-flow-analyzer/
├── analyzer.pl              # メインスクリプト
├── lib/
│   ├── VariableResolver.pm  # 変数展開モジュール
│   ├── Analyzer/            # 言語別解析モジュール
│   │   ├── Base.pm          # 基底クラス
│   │   ├── Sh.pm            # Shell解析
│   │   ├── Csh.pm           # C Shell解析
│   │   ├── Cobol.pm         # COBOL解析
│   │   └── Plsql.pm         # PL/SQL解析
│   ├── LanguageDetector.pm  # 言語自動判定
│   ├── DependencyResolver.pm # 依存関係解決
│   ├── FileMapper.pm        # ファイル名→パス解決
│   └── Output/              # 出力モジュール
│       ├── Flowchart.pm     # Mermaidフロー図
│       ├── Csv.pm           # CSV出力
│       ├── Json.pm          # JSON出力
│       └── Logger.pm        # ログ出力
└── README.md
```

## 変数展開機能

### 概要

スクリプト内で使用されている環境変数や変数を展開して、呼び出し階層を深く解析できます。

### 対応する変数パターン

| パターン | 例 | 対応 |
|----------|-----|------|
| 単純代入 | `VAR=/path/to/dir` | ✅ |
| 変数参照代入 | `VAR2=${VAR}/subdir` | ✅ |
| ダブルクォート | `VAR="value"` | ✅ |
| シングルクォート | `VAR='value'` | ✅ |
| ${VAR}形式 | `${BATCH_HOME}/job` | ✅ |
| $VAR形式 | `$BATCH_HOME/job` | ✅ |
| csh set | `set VAR=value` | ✅ |
| csh setenv | `setenv VAR value` | ✅ |

### 変数解決の優先順位

変数の値は以下の優先順位で解決されます：

1. `--env` または `--env-file` で明示的に指定された値（最優先）
2. スクリプト内で定義された値
3. 実行環境の環境変数（`%ENV`）
4. 未解決の場合は元の形式のまま（ログに警告を出力）

### 使用例

**スクリプト例（main.sh）:**
```bash
#!/bin/bash
BATCH_HOME=/opt/batch
SCRIPT_DIR=/home/scripts

# 変数を使った呼び出し
source ${BATCH_HOME}/lib/common.sh
${SCRIPT_DIR}/process.sh
```

**実行:**
```bash
perl analyzer.pl \
  --input file_list.txt \
  --output ./output/ \
  --env "BATCH_HOME=/opt/batch" \
  --env "SCRIPT_DIR=/home/app/scripts"
```

これにより、`${BATCH_HOME}/lib/common.sh` は `/opt/batch/lib/common.sh` に展開され、
`${SCRIPT_DIR}/process.sh` は `/home/app/scripts/process.sh` に展開されて解析されます。

## トラブルシューティング

### 「ファイルが見つかりません」エラー

解析対象のファイルパスが正しいか確認してください。相対パスではなく絶対パスで指定してください。

### 「言語判定失敗」警告

ファイルの拡張子またはshebangが正しくない可能性があります。以下の拡張子に対応しています：
- Shell: `.sh`, `.bash`
- C Shell: `.csh`, `.tcsh`
- COBOL: `.cbl`, `.cob`
- PL/SQL: `.pls`, `.sql`

### 「呼び出し先未解決」警告

呼び出されているスクリプトが見つからない場合に表示されます。以下を確認してください：
- スクリプトファイルが実際に存在するか
- ファイル名が正しいか
- 検索パスに含まれているか

## 制限事項

- 完全に動的なパス生成（実行時に計算される値）は解析できません
- `eval`実行や動的SQLは検出できません
- DB操作の検出は基本的なパターンのみに対応しています
- 変数の値が複雑なコマンド置換（`$(command)`）で設定される場合、展開できない可能性があります

詳細は `docs/SPECIFICATION.md` を参照してください。

## ライセンス

MIT License

## 作者

Takuma0222

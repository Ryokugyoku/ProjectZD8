"""指標 ID と上限値の定義。"""

CYCLOMATIC = "cyclomatic"
COGNITIVE = "cognitive"
NESTING = "nesting"
FUNCTION_LENGTH = "function_length"
FUNCTION_COUNT = "function_count"
FILE_LINES = "file_lines"
LONG_LINES = "long_lines"

# 1関数ごとの指標と上限。
FUNCTION_LIMITS = {
    CYCLOMATIC: 10,
    COGNITIVE: 15,
    NESTING: 3,
    FUNCTION_LENGTH: 80,
}

# 1ファイルごとの指標と上限。
FILE_LIMITS = {
    FUNCTION_COUNT: 20,
    FILE_LINES: 500,
    LONG_LINES: 0,
}

# 計測対象の拡張子。
SWIFT_SUFFIX = ".swift"

# `--update-baseline` が走査するルート直下のディレクトリ。
BASELINE_SCAN_DIRS = (
    "ProjectZD8",
    "ProjectZD8Tests",
    "ProjectZD8UITests",
    "RecordingSessionLiveActivity",
)

# ルートからのベースラインファイルの相対パス。
BASELINE_RELATIVE_PATH = "Tools/CodeMetrics/baseline.json"

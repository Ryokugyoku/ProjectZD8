"""本ツール自身のメッセージを標準エラーへ出す。コマンドの出力とは混ぜない。"""

import sys

NOTE_PREFIX = "run_xcodebuild: "


def report_line(line: str) -> None:
    """責務: 先頭語を含む1行(`TIMEOUT` など)を、そのまま標準エラーへ出す。"""
    print(line, file=sys.stderr, flush=True)


def report_note(message: str) -> None:
    """責務: 補足メッセージを、本ツールの名前を付けて標準エラーへ出す。"""
    report_line(NOTE_PREFIX + message)

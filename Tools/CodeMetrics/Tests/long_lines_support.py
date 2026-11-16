"""long_lines テスト共通の補助。行とソースの組み立て、期待する出力行の組み立てだけを担う。"""

LIMIT = 160
SHORT = "let a = 1"


def line_of(length, head="//"):
    """責務: 先頭が head で、文字数がちょうど length の行(改行なし)を作る。"""
    return head + "x" * (length - len(head))


def source_with(long_at, total, length=LIMIT + 1):
    """責務: total 行のうち long_at(1 始まり)の行だけを length 文字にしたソースを作る。"""
    rows = [line_of(length) if i + 1 in long_at else SHORT for i in range(total)]
    return "\n".join(rows) + "\n"


def expected(path, first, count, numbers):
    """責務: README §6 の long_lines エラー行(括弧は numbers をそのまま並べる)を作る。"""
    return "%s:%d: error: long_lines %d > 0 (lines %s)" % (path, first, count, numbers)

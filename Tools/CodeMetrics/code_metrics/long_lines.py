"""160文字を超える行(長い行)を見つける。"""

from typing import List

MAX_LINE_CHARS = 160


def long_line_numbers(text: str) -> List[int]:
    """責務: 文字数が上限を超える行の番号(1 始まり、昇順)を返す。"""
    if not text:
        return []
    lines = text.split("\n")
    if text.endswith("\n"):
        lines.pop()
    found = []
    for number, line in enumerate(lines, start=1):
        if line.endswith("\r"):
            line = line[:-1]
        if len(line) > MAX_LINE_CHARS:
            found.append(number)
    return found

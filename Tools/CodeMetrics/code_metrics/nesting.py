"""関数ごとの制御構造のネスト(最大段数)を数える。"""

from typing import List, Optional

from .tokenizer import Token, TokenStream

_CONTROL = frozenset(
    {"if", "else", "guard", "switch", "for", "while", "do", "catch"}
)
_FUNC_KEYWORDS = frozenset({"func", "init", "subscript", "deinit"})
_ACCESSORS = frozenset({"get", "set", "willSet", "didSet"})
_PAREN_OPEN = frozenset("([")
_PAREN_CLOSE = frozenset(")]")


def _is_dotted(tokens: List[Token], i: int) -> bool:
    """責務: トークン i の直前が `.`(メンバー参照)かを返す。"""
    return i > 0 and tokens[i - 1].text == "."


def _is_accessor_brace(tokens: List[Token], i: int) -> bool:
    """責務: `{` (位置 i)が get/set/willSet/didSet の本体かを返す。"""
    prev = tokens[i - 1]
    if prev.kind == "word":
        return prev.text in _ACCESSORS
    if prev.text == ")" and i >= 4:
        return tokens[i - 4].text in _ACCESSORS and tokens[i - 3].text == "("
    return False


def _matching_close(tokens: List[Token], i: int) -> int:
    """責務: 位置 i の `{` に対応する `}` の位置を返す(なければ末尾)。"""
    depth = 0
    for j in range(i, len(tokens)):
        text = tokens[j].text
        depth += (text == "{") - (text == "}")
        if tokens[j].kind == "punct" and depth == 0:
            return j
    return len(tokens) - 1


class _Walker:
    """関数本体のトークンを順に読み、制御構造の段数の最大値を求める。"""

    def __init__(self, tokens: List[Token]) -> None:
        """責務: 走査状態を初期化する。"""
        self.tokens = tokens
        self.frames: List[tuple] = []
        self.paren = 0
        self.pending: Optional[str] = None
        self.depth = 0
        self.best = 0
        self.repeat_tail = False
        self._after_repeat = False

    def walk(self, start: int) -> int:
        """責務: 位置 start の本体 `{` から閉じるまでの最大段数を返す。"""
        i = start
        while i < len(self.tokens):
            i = self._step(i)
            if i > start and not self.frames:
                break
        return self.best

    def _step(self, i: int) -> int:
        """責務: トークン i を処理して次に読む位置を返す。"""
        token = self.tokens[i]
        self.repeat_tail = self._after_repeat
        self._after_repeat = False
        if token.kind == "word":
            self._word(i)
        elif token.text == "{":
            return self._open(i)
        elif token.text == "}":
            self._close()
        elif token.text in _PAREN_OPEN:
            self.paren += 1
        elif token.text in _PAREN_CLOSE:
            self.paren = max(0, self.paren - 1)
        elif token.text == ";":
            self.pending = None
        return i + 1

    def _word(self, i: int) -> None:
        """責務: キーワードなら、次の `{` の種別を予約する。"""
        text = self.tokens[i].text
        if _is_dotted(self.tokens, i):
            return
        if text == "repeat":
            self.pending = "repeat"
        elif text == "while" and self.repeat_tail:
            return
        elif text in _CONTROL:
            self.pending = "control"
        elif text in _FUNC_KEYWORDS:
            self.pending = "func"

    def _brace_kind(self, i: int) -> str:
        """責務: 位置 i の `{` の種別(control/repeat/func/other)を返す。"""
        if self.paren > 0:
            return "other"
        if self.pending:
            return self.pending
        if len(self.frames) == 1 and _is_accessor_brace(self.tokens, i):
            return "func"
        return "other"

    def _open(self, i: int) -> int:
        """責務: `{` を処理して次に読む位置を返す。func は本体ごと飛ばす。"""
        kind = self._brace_kind(i)
        self.pending = None
        if kind == "func" and self.frames:
            return _matching_close(self.tokens, i) + 1
        self.frames.append((kind, self.paren))
        self.paren = 0
        if kind in ("control", "repeat"):
            self.depth += 1
            self.best = max(self.best, self.depth)
        return i + 1

    def _close(self) -> None:
        """責務: `}` を処理して直前の段へ戻る。"""
        if not self.frames:
            return
        kind, paren = self.frames.pop()
        self.paren = paren
        if kind in ("control", "repeat"):
            self.depth -= 1
        self._after_repeat = kind == "repeat"


def _body_start(tokens: List[Token], name: str) -> Optional[int]:
    """責務: 関数本体の `{` の位置を返す(括弧の外の最初の `{`)。"""
    i = 0
    if name in _ACCESSORS:
        i = _after_accessor_name(tokens, name)
    paren = 0
    for j in range(i, len(tokens)):
        text = tokens[j].text
        if text in _PAREN_OPEN:
            paren += 1
        elif text in _PAREN_CLOSE:
            paren = max(0, paren - 1)
        elif text == "{" and paren == 0:
            return j
    return None


def _after_accessor_name(tokens: List[Token], name: str) -> int:
    """責務: accessor 名の単語トークンの位置を返す(なければ 0)。"""
    for j, token in enumerate(tokens):
        if token.kind == "word" and token.text == name:
            return j
    return 0


def function_nesting(
    stream: TokenStream, name: str, start_line: int, end_line: int
) -> int:
    """責務: 行範囲の関数について制御構造のネストの最大段数を返す。"""
    tokens = stream.slice_lines(start_line, end_line)
    start = _body_start(tokens, name)
    if start is None:
        return 0
    return _Walker(tokens).walk(start)

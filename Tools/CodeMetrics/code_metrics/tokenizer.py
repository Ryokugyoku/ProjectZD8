"""Swift ソースを、コメントと文字列リテラルを除いたトークン列へ分解する。"""

import bisect
import re
from dataclasses import dataclass
from typing import Dict, List, Set

# 出力する記号トークン。それ以外の記号は捨てる。
_PUNCT = frozenset("{}()[];.")

_TOKEN_RE = re.compile(
    r"(?P<nl>\n)"
    r"|(?P<ws>[ \t\r]+)"
    r"|(?P<lc>//[^\n]*)"
    r"|(?P<bc>/\*)"
    r"|(?P<str>#*\")"
    r"|(?P<bt>`[^`\n]*`)"
    r"|(?P<word>#?[A-Za-z_$][\w$]*)"
    r"|(?P<num>\d\w*)"
    r"|(?P<punct>.)",
    re.S,
)


@dataclass(frozen=True)
class Token:
    """1個のトークン。kind は "word" か "punct"。line は 1 始まり。"""

    kind: str
    text: str
    line: int


class TokenStream:
    """行番号で範囲を引けるトークン列。"""

    def __init__(self, tokens: List[Token]) -> None:
        """責務: トークン列と行番号の索引を保持する。"""
        self.tokens = tokens
        self._lines = [t.line for t in tokens]

    def slice_lines(self, start: int, end: int) -> List[Token]:
        """責務: 行 start から end(両端含む)にあるトークンを返す。"""
        lo = bisect.bisect_left(self._lines, start)
        hi = bisect.bisect_right(self._lines, end)
        return self.tokens[lo:hi]

    def words_by_line(self) -> Dict[int, Set[str]]:
        """責務: 行番号ごとに、その行にある単語トークンの集合を返す。"""
        result: Dict[int, Set[str]] = {}
        for token in self.tokens:
            if token.kind == "word":
                result.setdefault(token.line, set()).add(token.text)
        return result


class _Scanner:
    """ソース全体を1回走査してトークンを集める。"""

    def __init__(self, source: str) -> None:
        """責務: 走査状態と改行位置の索引を初期化する。"""
        self.src = source
        self.pos = 0
        self.tokens: List[Token] = []
        self._newlines = [i for i, c in enumerate(source) if c == "\n"]

    def line_of(self, pos: int) -> int:
        """責務: 文字位置の行番号(1 始まり)を返す。"""
        return bisect.bisect_left(self._newlines, pos) + 1

    def run(self) -> List[Token]:
        """責務: 末尾まで走査してトークン列を返す。"""
        handlers = {
            "bc": self._block_comment,
            "str": self._string,
            "word": self._word,
            "punct": self._punct,
        }
        while self.pos < len(self.src):
            match = _TOKEN_RE.match(self.src, self.pos)
            handler = handlers.get(match.lastgroup)
            if handler is None:
                self.pos = match.end()
            else:
                handler(match)
        return self.tokens

    def _emit(self, kind: str, text: str, pos: int) -> None:
        """責務: トークンを1個追加する。"""
        self.tokens.append(Token(kind, text, self.line_of(pos)))

    def _word(self, match: "re.Match") -> None:
        """責務: 単語トークンを追加する。"""
        self._emit("word", match.group(), match.start())
        self.pos = match.end()

    def _punct(self, match: "re.Match") -> None:
        """責務: 対象の記号だけをトークンとして追加する。"""
        if match.group() in _PUNCT:
            self._emit("punct", match.group(), match.start())
        self.pos = match.end()

    def _block_comment(self, match: "re.Match") -> None:
        """責務: 入れ子を許す /* */ コメントを読み飛ばす。"""
        depth = 0
        i = match.start()
        n = len(self.src)
        while i < n:
            if self.src.startswith("/*", i):
                depth += 1
                i += 2
            elif self.src.startswith("*/", i):
                depth -= 1
                i += 2
                if depth == 0:
                    break
            else:
                i += 1
        self.pos = min(i, n)

    def _string(self, match: "re.Match") -> None:
        """責務: 文字列リテラル(複数行・raw を含む)を読み飛ばす。"""
        hashes = len(match.group()) - 1
        self.pos = self._skip_string(match.end() - 1, hashes)

    def _skip_string(self, quote_pos: int, hashes: int) -> int:
        """責務: quote_pos の引用符で始まる文字列の終端の次の位置を返す。"""
        src = self.src
        multi = src.startswith('"""', quote_pos)
        opener = '"""' if multi else '"'
        close = opener + "#" * hashes
        escape = "\\" + "#" * hashes
        i = quote_pos + len(opener)
        while i < len(src):
            if src.startswith(close, i):
                return i + len(close)
            if src.startswith(escape, i):
                i = self._skip_escape(i + len(escape))
            elif src[i] == "\n" and not multi:
                return i
            else:
                i += 1
        return len(src)

    def _skip_escape(self, i: int) -> int:
        """責務: バックスラッシュ直後の位置から、エスケープ列の終端を返す。"""
        if i < len(self.src) and self.src[i] == "(":
            return self._skip_interpolation(i)
        return i + 1

    def _skip_interpolation(self, i: int) -> int:
        """責務: `\\(` の括弧位置 i から、対応する `)` の次の位置を返す。"""
        depth = 0
        n = len(self.src)
        while i < n:
            ch = self.src[i]
            if ch == '"':
                i = self._skip_string(i, 0)
                continue
            depth += (ch == "(") - (ch == ")")
            i += 1
            if depth == 0:
                break
        return i


def tokenize(source: str) -> TokenStream:
    """責務: Swift ソースをコメント・文字列を除いたトークン列にする。"""
    return TokenStream(_Scanner(source).run())

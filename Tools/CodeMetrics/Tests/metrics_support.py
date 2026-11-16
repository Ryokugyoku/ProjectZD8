"""CodeMetrics テスト共通の補助。CLI の起動と Swift フィクスチャの組み立てだけを担う。"""

import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[3]
TOOL = REPO / "Tools" / "CodeMetrics" / "check_swift_metrics.py"
TIMEOUT = 60
BASELINE_REL = "Tools/CodeMetrics/baseline.json"


class Result:
    """CLI 実行結果。標準出力と標準エラーを両方保持する。"""

    def __init__(self, completed):
        self.code = completed.returncode
        self.stdout = completed.stdout
        self.stderr = completed.stderr

    @property
    def lines(self):
        """責務: 標準出力と標準エラーを合わせた空行を除く行を返す。"""
        text = self.stdout + "\n" + self.stderr
        return [ln for ln in text.splitlines() if ln.strip()]

    @property
    def errors(self):
        """責務: error: を含む行だけを返す。"""
        return [ln for ln in self.lines if ": error: " in ln]

    @property
    def warnings(self):
        """責務: warning: を含む行だけを返す。"""
        return [ln for ln in self.lines if ": warning: " in ln]


def tool_env(root, env=None):
    """責務: 既存の環境(env か os.environ)に CODE_METRICS_ROOT=root を足した環境を返す。"""
    merged = dict(os.environ if env is None else env)
    merged["CODE_METRICS_ROOT"] = str(root)
    return merged


def run_tool(root, *args, stdin=None, env=None, cwd=None):
    """責務: ルートを環境変数で指定してツールを CLI 経由で起動する(必ずタイムアウト付き)。"""
    cmd = [sys.executable, str(TOOL)] + [str(a) for a in args]
    done = subprocess.run(cmd, input=stdin, timeout=TIMEOUT, cwd=cwd,
                          capture_output=True, text=True,
                          env=tool_env(root, env))
    return Result(done)


def run_git(root, *args):
    """責務: 作成者設定つきで git を root で実行し標準出力を返す(タイムアウト付き)。"""
    cmd = ["git", "-c", "user.name=t", "-c", "user.email=t@example.com",
           "-c", "commit.gpgsign=false", "-C", str(root)] + list(args)
    done = subprocess.run(cmd, timeout=TIMEOUT, check=True,
                          capture_output=True, text=True)
    return done.stdout.strip()


def make_root(case):
    """責務: テスト終了時に消える一時ルート(実パス)を作る。"""
    tmp = tempfile.TemporaryDirectory()
    case.addCleanup(tmp.cleanup)
    return Path(os.path.realpath(tmp.name))


def write(root, rel, text):
    """責務: ルート配下に UTF-8 でファイルを書き、そのパスを返す。"""
    path = Path(root) / rel
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(text.encode("utf-8"))
    return path


def swift_func(body, name="f", prefix=""):
    """責務: 本体を持つ関数宣言を組み立てる。宣言は prefix の次の行になる。"""
    return prefix + "func %s() {\n%s\n}\n" % (name, body)


def nested_ifs(depth):
    """責務: depth 段の if の入れ子(最大ネスト=depth)を作る。"""
    opens = ["if c%d {" % i for i in range(depth)]
    return "\n".join(opens + ["work()"] + ["}"] * depth)


def flat_ifs(count, start=0):
    """責務: 互いに独立した if を count 個並べる(各 CCN+1)。"""
    return "\n".join("if g%d { work() }" % (start + i) for i in range(count))


def body_of_length(total):
    """責務: 宣言と閉じ括弧を含め total 行になる関数を作る。"""
    return swift_func("\n".join(["work()"] * (total - 2)))


class MetricsTestCase(unittest.TestCase):
    """一時ルートとツール実行の近道を持つ基底クラス。"""

    def setUp(self):
        self.root = make_root(self)

    def check_swift(self, source, rel="ProjectZD8/A.swift"):
        """責務: ソースを書いてそのファイルだけをチェックする。"""
        path = write(self.root, rel, source)
        return run_tool(self.root, path)

    def assert_clean(self, result):
        """責務: 出力なし・終了コード 0 を検証する。"""
        self.assertEqual(result.lines, [])
        self.assertEqual(result.code, 0)

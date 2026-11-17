"""残ったロックの回収テスト(README §3)。持ち主のいないロックは消して取り直し、持ち主がいる/新しいロックは消さない。"""

import os
import shutil
import subprocess
import time

from runner_support import TOUCH, RunnerTestCase, assert_lock_released, pid_alive

BROKEN_PID_CONTENTS = {"pid が無い": None, "pid が空": "", "pid が数字でない": "abc"}


class DeadOwnerLockTests(RunnerTestCase):
    """pid のプロセスが存在しないロックは、すぐ回収して実行する。"""

    def dead_pid(self):
        """責務: 終了・回収済みで、今は存在しないプロセスの PID を返す。"""
        proc = subprocess.Popen(self.py("pass"))
        proc.wait(timeout=10)
        self.assertFalse(pid_alive(proc.pid), "回収済みの PID が別のプロセスに再利用された")
        return proc.pid

    def run_with_dead_owner(self, lock_wait):
        """責務: 存在しない PID のロックを置き、--lock-wait lock_wait で子を実行した結果を返す。"""
        self.write_lock(str(self.dead_pid()))
        self.touched = self.path("touched")
        env = self.env(XCODE_TEST_RUNNER_POLL_SECONDS="3")
        args = ["--limit", "10", "--lock-wait", str(lock_wait), "--"] + self.py(TOUCH, self.touched)
        return self.run_runner(args, env=env)

    def test_存在しないPIDのロックはすぐ回収して実行する(self):
        """責務: 取り直し間隔を 3 秒にしても、その間隔を待たずに回収して実行し、終了後はロックが無い。"""
        result = self.run_with_dead_owner(10)
        self.assertEqual(result.code, 0, result.stderr)
        self.assertTrue(self.touched.exists(), "回収後にコマンドが実行されなかった")
        self.assertLess(result.elapsed, 2.5, "回収を取り直し間隔の後まで遅らせた")
        assert_lock_released(self)

    def test_lock_wait_0でも存在しないPIDのロックは回収して実行する(self):
        """責務: 回収は「すぐ取り直す」ので、待たない指定(--lock-wait 0)でも実行される。"""
        result = self.run_with_dead_owner(0)
        self.assertEqual(result.code, 0, result.stderr)
        self.assertTrue(self.touched.exists(), "回収後にコマンドが実行されなかった")
        assert_lock_released(self)


class BrokenPidLockTests(RunnerTestCase):
    """pid が無い・空・数字でないロックは、更新時刻が STALE_SECONDS より古い時だけ回収する。"""

    def write_broken_lock(self, content, age):
        """責務: 前のロックを片付けてから中身 content(None なら pid ファイル無し)のロックを作り、更新時刻を age 秒前にする。"""
        if self.lock_dir.exists():
            shutil.rmtree(str(self.lock_dir))
        self.write_lock(content)
        stamp = time.time() - age
        os.utime(str(self.lock_dir), (stamp, stamp))

    def run_child(self, touched, lock_wait, stale):
        """責務: STALE_SECONDS=stale・--lock-wait lock_wait で、目印を作る子を実行した結果を返す。"""
        env = self.env(XCODE_TEST_RUNNER_STALE_SECONDS=str(stale))
        args = ["--limit", "10", "--lock-wait", str(lock_wait), "--"] + self.py(TOUCH, touched)
        return self.run_runner(args, env=env)

    def test_古ければ回収して実行する(self):
        """責務: 更新時刻が STALE_SECONDS(1秒)より古い壊れたロックは、回収して実行し、終了後は残らない。"""
        for name, content in BROKEN_PID_CONTENTS.items():
            with self.subTest(name):
                self.write_broken_lock(content, age=10)
                touched = self.path("touched-" + name)
                result = self.run_child(touched, lock_wait=5, stale=1)
                self.assertEqual(result.code, 0, result.stderr)
                self.assertTrue(touched.exists(), "古いロックが回収されずコマンドが実行されなかった")
                assert_lock_released(self)

    def test_新しければ回収せずに待つ(self):
        """責務: 更新時刻が STALE_SECONDS(30秒)より新しい壊れたロックは回収せず、--lock-wait 1 の後 125。"""
        for name, content in BROKEN_PID_CONTENTS.items():
            with self.subTest(name):
                self.write_broken_lock(content, age=0)
                touched = self.path("touched-" + name)
                result = self.run_child(touched, lock_wait=1, stale=30)
                self.assertEqual(result.code, 125, result.stderr)
                self.assertFalse(touched.exists(), "新しいロックが回収されてコマンドが実行された")
                self.assertTrue(self.lock_dir.is_dir(), "新しいロックが消された")

    def test_待っている間に古くなれば回収して実行する(self):
        """責務: 作りたての壊れたロックは STALE_SECONDS(1秒)たつまで回収されず、その後に回収して実行する。"""
        self.write_broken_lock(None, age=0)
        touched = self.path("touched")
        result = self.run_child(touched, lock_wait=8, stale=1)
        self.assertEqual(result.code, 0, result.stderr)
        self.assertTrue(touched.exists(), "古くなったロックが回収されなかった")
        self.assertGreaterEqual(result.elapsed, 0.9, "STALE_SECONDS より前に回収した")
        assert_lock_released(self)

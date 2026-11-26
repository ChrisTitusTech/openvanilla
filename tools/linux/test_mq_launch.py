"""Exercise launcher reruns without starting Wine or touching the desktop."""
import os
import subprocess
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).with_name("mq-launch.sh")


class LauncherRerun(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        bin_dir = self.root / "bin"
        bin_dir.mkdir()
        self.env = dict(os.environ, PATH=f"{bin_dir}:{os.environ['PATH']}",
                        DISPLAY=":mock", MQ_LAUNCH_CONF=str(self.root / "no-conf"),
                        EQ_DIR=str(self.root / "eq"), MQ_DIR=str(self.root / "mq"),
                        EQ_INSTANCES=str(self.root / "instances"),
                        STEAM_COMPAT_DATA_PATH=str(self.root / "compat"),
                        PROTON=str(bin_dir / "proton"), GS_RES="1920x1050",
                        GAMESCOPE="0", LOGIN_TIMEOUT="0", LAUNCH_DELAY="0",
                        WINDOW_TIMEOUT="5", FIXTURE=str(self.root),
                        EXISTING_PID=str(os.getpid()))
        for directory, filename in [(self.root / "eq", "eqgame.exe"),
                                    (self.root / "mq", "MacroQuest.exe")]:
            directory.mkdir()
            (directory / filename).touch()
        (self.root / "instances" / "tag3").mkdir(parents=True)
        (self.root / "instances" / "tag3" / "eqclient.ini").write_text("unchanged\n")
        self.stub(bin_dir / "pgrep", 'if [[ $1 == -x ]]; then echo "$EXISTING_PID"; fi\nexit 0\n')
        self.stub(bin_dir / "wmctrl", '''case "$1" in
            -lp) printf '0x0001 2 %s host Existing.Server (Lvl:100 Monk)\n' "$EXISTING_PID" ;;
            -lx) if [[ -e "$FIXTURE/started" ]]; then
                printf '0x0002 3 steam_app_205710.EverQuest host EverQuest\n'
            fi ;;
            *) printf '%s\n' "$*" >> "$FIXTURE/window-actions" ;;
        esac
        exit 0
        ''')
        self.stub(bin_dir / "proton", 'printf "%s\\n" "$*" >> "$FIXTURE/start-args"\ntouch "$FIXTURE/started"\n')
        wine = bin_dir / "files" / "bin" / "wine"
        wine.parent.mkdir(parents=True)
        self.stub(wine, "exit 0\n")

    @staticmethod
    def stub(path, body):
        path.write_text("#!/usr/bin/env bash\n" + body)
        path.chmod(0o755)

    def launch(self, tags, chars):
        return subprocess.run([str(SCRIPT)], env=dict(self.env, TAGS=tags, CHARS=chars),
                              text=True, capture_output=True, timeout=15)

    def test_only_missing_slot_is_launched(self):
        result = self.launch("3 4", "server:existing server:missing")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("launched 1 clients; skipped 1 already running", result.stdout)
        self.assertIn("/login:server:missing", (self.root / "start-args").read_text())
        self.assertNotIn("/login:server:existing", (self.root / "start-args").read_text())
        self.assertEqual((self.root / "instances/tag3/eqclient.ini").read_text(), "unchanged\n")
        self.assertNotIn("0x0001", (self.root / "window-actions").read_text())

    def test_existing_character_moved_to_another_tag(self):
        result = self.launch("4", "server:existing")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("launched 0 clients; skipped 1 already running", result.stdout)
        self.assertFalse((self.root / "started").exists())
        self.assertFalse((self.root / "window-actions").exists())

    def test_tag_conflict_does_not_launch(self):
        result = self.launch("3", "server:different")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("occupied by a different", result.stderr)
        self.assertFalse((self.root / "started").exists())

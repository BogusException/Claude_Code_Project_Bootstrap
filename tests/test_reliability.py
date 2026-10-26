"""Linux regression tests: no user HOME override or real remote publication."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import stat
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
REAL_GIT = shutil.which("git")
REAL_PYTHON = shutil.which("python3")
BASE_ENV = {
    **os.environ,
    "GIT_CONFIG_GLOBAL": "/dev/null",
    "GIT_CONFIG_NOSYSTEM": "1",
    "GIT_AUTHOR_NAME": "Bootstrap test",
    "GIT_AUTHOR_EMAIL": "test@example.invalid",
    "GIT_COMMITTER_NAME": "Bootstrap test",
    "GIT_COMMITTER_EMAIL": "test@example.invalid",
    "STY": "isolated-test",
}

def command(*args, cwd=None, env=None, data=None, ok=True):
    environment = {**BASE_ENV, **(env or {})}
    environment = {key: value for key, value in environment.items() if value is not None}
    result = subprocess.run(
        list(map(str, args)), cwd=cwd, env=environment,
        input=data, text=True, capture_output=True, timeout=45,
    )
    if ok and result.returncode:
        raise AssertionError(f"{args[0:3]} exited {result.returncode}: {result.stderr[-3000:]}\n{result.stdout[-1000:]}")
    return result

def git(path, *args, **kwargs):
    return command(REAL_GIT, "-C", path, *args, **kwargs)

def fixture_repo(path):
    path.mkdir(parents=True)
    git(path, "init", "-q", "-b", "main")
    (path/"README.md").write_text("seed\n")
    git(path, "add", "README.md")
    git(path, "commit", "-qm", "Initial project scaffold")
    return path

def snapshot(path):
    if not path.exists():
        return None
    if path.is_file():
        s = path.stat()
        return s.st_mode, s.st_mtime_ns, hashlib.sha256(path.read_bytes()).hexdigest()
    return sorted(p.name for p in path.iterdir())

class ReliabilityTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="mkproj-regression-")
        self.base = Path(self.temp.name)

    def tearDown(self):
        self.temp.cleanup()

    def shell(self, text, *args, **kwargs):
        return command("bash", "-c", 'set -euo pipefail; source "$1/bootstrap.sh"; shift; '+text,
                       "test", ROOT, *args, **kwargs)

    def test_dry_run_writes_nothing(self):
        work = self.base/"work"; work.mkdir()
        result = command("bash", ROOT/"bootstrap.sh", "--dry-run", "--agent=none", "sample",
                         cwd=work, env={"MKPROJ_REPOSITORIES_DIR":str(self.base/"repos")})
        self.assertIn("DRY RUN", result.stdout)
        self.assertEqual(list(work.iterdir()), [])
        self.assertFalse((self.base/"repos").exists())

    def test_invalid_new_options(self):
        for options in [("--agent=unknown",),("--agent=codex","--agent=none"),
                        ("--doctor","--no-global"),("--dry-run","--test"),
                        ("--test","--agent=none"),("--no-global","--no-global")]:
            with self.subTest(options=options):
                result = command("bash",ROOT/"bootstrap.sh",*options,cwd=self.base,ok=False)
                self.assertNotEqual(result.returncode,0)
                self.assertEqual(list(self.base.iterdir()), [])

    def test_isolated_test_never_pushes_or_changes_user_globals(self):
        sensitive = [Path.home()/".bashrc",Path.home()/".claude/settings.json",
                     Path.home()/"bin/mkproj",Path.home()/"Repositories"]
        before = [snapshot(p) for p in sensitive]
        wrappers = self.base/"bin"; wrappers.mkdir()
        marker = self.base/"push-attempt"
        (wrappers/"git").write_text(
            '#!/bin/bash\nfor arg in "$@"; do if [[ "$arg" == push ]]; then touch "'+str(marker)+'"; exit 91; fi; done\nexec "'+REAL_GIT+'" "$@"\n')
        (wrappers/"git").chmod(0o755)
        result = command("bash",ROOT/"bootstrap.sh","--test",cwd=self.base,
                         env={"TMPDIR":str(self.base),"PATH":str(wrappers)+":"+os.environ["PATH"]})
        self.assertIn("All checks passed",result.stdout)
        self.assertFalse(marker.exists())
        self.assertEqual([snapshot(p) for p in sensitive],before)
        self.assertEqual(list(self.base.glob("mkproj-test.*")),[])

    def test_failure_cleans_test_artifacts_and_reports_phase(self):
        wrappers=self.base/"bin"; wrappers.mkdir()
        (wrappers/"python3").write_text(
            '#!/bin/bash\nif [[ "$1" == -m && "$2" == venv ]]; then exit 7; fi\nexec "'+REAL_PYTHON+'" "$@"\n')
        (wrappers/"python3").chmod(0o755)
        result=command("bash",ROOT/"bootstrap.sh","--test",cwd=self.base,
                       env={"TMPDIR":str(self.base),"PATH":str(wrappers)+":"+os.environ["PATH"]},ok=False)
        self.assertEqual(result.returncode,7)
        self.assertIn("phase python",result.stderr)
        self.assertEqual(list(self.base.glob("mkproj-test.*")),[])

    def test_bare_collision_preserves_destination(self):
        bare=self.base/"existing.git"
        command(REAL_GIT,"init","--bare","-q",bare)
        before=snapshot(bare/"config")
        result=self.shell('PROJECT_DIR="$1/project"; SETUP_LOCAL_REPO=true; BARE_REPO="$1/existing.git"; check_repo_destination',
                          self.base,ok=False)
        self.assertNotEqual(result.returncode,0)
        self.assertIn("collision",result.stderr)
        self.assertEqual(snapshot(bare/"config"),before)
        self.assertFalse((self.base/"project").exists())

    def test_mismatched_origin_is_never_rewritten(self):
        repo=fixture_repo(self.base/"project")
        git(repo,"remote","add","origin",str(self.base/"other.git"))
        before=(repo/".git/config").read_bytes()
        result=self.shell('PROJECT_DIR="$1"; SETUP_LOCAL_REPO=true; BARE_REPO="$2"; check_repo_destination',
                          repo,self.base/"new.git",ok=False)
        self.assertNotEqual(result.returncode,0)
        self.assertEqual((repo/".git/config").read_bytes(),before)

    def test_matching_origin_can_resume_with_remote_tracking_refs(self):
        repo=fixture_repo(self.base/"project"); bare=self.base/"origin.git"
        command(REAL_GIT,"init","--bare","-q",bare)
        git(repo,"remote","add","origin",str(bare));git(repo,"push","-qu","origin","main")
        self.shell('PROJECT_DIR="$1"; SETUP_LOCAL_REPO=true; BARE_REPO="$2"; check_repo_destination',
                   repo,bare)

    def test_real_commits_dirty_index_and_detached_head_are_refused(self):
        for kind in ["real","dirty","staged","detached"]:
            with self.subTest(kind=kind):
                repo=fixture_repo(self.base/kind)
                if kind in ["real","dirty","staged"]:
                    (repo/"README.md").write_text("changed\n")
                if kind in ["real","staged"]:git(repo,"add","README.md")
                if kind=="real":git(repo,"commit","-qm","Real project work")
                if kind=="detached":git(repo,"checkout","--detach","-q")
                result=self.shell('PROJECT_DIR="$1"; check_project_repo',repo,ok=False)
                self.assertNotEqual(result.returncode,0)

    def test_nested_repo_and_non_bare_destination_are_refused(self):
        parent=fixture_repo(self.base/"parent")
        result=self.shell('PROJECT_DIR="$1/child"; check_project_repo',parent,ok=False)
        self.assertNotEqual(result.returncode,0)
        result=self.shell('PROJECT_DIR="$1/new"; SETUP_LOCAL_REPO=true; BARE_REPO="$1/parent"; check_repo_destination',
                          self.base,ok=False)
        self.assertNotEqual(result.returncode,0)

    def test_forced_private_index_entries_are_rejected(self):
        repo=fixture_repo(self.base/"project")
        git(repo,"config","core.hooksPath",str(ROOT/"templates/git-hooks"))
        head=git(repo,"rev-parse","HEAD").stdout
        shutil.copy(ROOT/"templates/.gitignore",repo/".gitignore")
        paths=["runtime.log","build/probe","responses/private.txt","responses/private\nname.txt","backups/config.bak",
               ".venv/probe","secrets/key.pem",".env",".env.production",
               ".claude/settings.local.json",".codex/auth.json","responses/.gitkeep"]
        for path in paths:
            with self.subTest(path=path):
                item=repo/path;item.parent.mkdir(parents=True,exist_ok=True);item.write_text("private\n")
                git(repo,"add","-f","--",path)
                result=git(repo,"commit","-qm","must be rejected",ok=False)
                self.assertNotEqual(result.returncode,0)
                self.assertIn("Refusing private path",result.stderr)
                self.assertEqual(git(repo,"rev-parse","HEAD").stdout,head)
                git(repo,"reset","-q","HEAD","--",path)
                item.unlink()
        (repo/".env.example").write_text("KEY=\n")
        git(repo,"add",".env.example");git(repo,"commit","-qm","Track safe example")

    def test_pre_push_catches_private_content_removed_in_later_commit(self):
        repo=fixture_repo(self.base/"project");bare=self.base/"remote.git"
        command(REAL_GIT,"init","--bare","-q",bare)
        git(repo,"remote","add","origin",str(bare));git(repo,"push","-q","origin","main")
        before=command(REAL_GIT,"--git-dir="+str(bare),"rev-parse","main").stdout
        private=repo/"responses/private.txt";private.parent.mkdir();private.write_text("private")
        git(repo,"add","-f","responses/private.txt");git(repo,"commit","-qm","Unsafe old commit")
        git(repo,"rm","-q","responses/private.txt");git(repo,"commit","-qm","Remove private file")
        git(repo,"config","core.hooksPath",str(ROOT/"templates/git-hooks"))
        result=git(repo,"push","origin","main",ok=False)
        self.assertNotEqual(result.returncode,0)
        self.assertIn("Refusing private path",result.stderr)
        self.assertEqual(command(REAL_GIT,"--git-dir="+str(bare),"rev-parse","main").stdout,before)

    def auto_fixture(self):
        repo=fixture_repo(self.base/"project");bare=self.base/"remote.git"
        command(REAL_GIT,"init","--bare","-q",bare)
        git(repo,"remote","add","origin",str(bare));git(repo,"push","-qu","origin","main")
        shutil.copytree(ROOT/"templates/git-hooks",repo/".githooks")
        git(repo,"add",".githooks");git(repo,"commit","-qm","Install guards")
        return repo,bare

    def test_auto_commit_never_stages_unrelated_files(self):
        repo,_=self.auto_fixture()
        head=git(repo,"rev-parse","HEAD").stdout
        (repo/"README.md").write_text("unstaged\n")
        (repo/"unrelated.txt").write_text("untracked")
        command("bash",ROOT/"templates/hooks/auto-commit.sh",env={"CLAUDE_PROJECT_DIR":str(repo)})
        self.assertEqual(git(repo,"rev-parse","HEAD").stdout,head)
        self.assertEqual(git(repo,"diff","--cached","--name-only").stdout,"")

    def test_auto_commit_staged_only_and_push_failure_is_visible(self):
        repo,bare=self.auto_fixture()
        (repo/"task.txt").write_text("intended")
        (repo/"unrelated.txt").write_text("leave alone")
        git(repo,"add","task.txt")
        command("bash",ROOT/"templates/hooks/auto-commit.sh",env={"CLAUDE_PROJECT_DIR":str(repo)})
        self.assertEqual(git(repo,"show","--format=","--name-only","HEAD").stdout.strip(),"task.txt")
        self.assertIn("unrelated.txt",git(repo,"status","--short").stdout)
        git(repo,"remote","set-url","origin",str(self.base/"missing.git"))
        (repo/"task.txt").write_text("next")
        git(repo,"add","task.txt")
        result=command("bash",ROOT/"templates/hooks/auto-commit.sh",
                       env={"CLAUDE_PROJECT_DIR":str(repo)},ok=False)
        self.assertNotEqual(result.returncode,0)
        self.assertIn("does not appear",result.stderr)

    def test_backup_failure_leaves_original_untouched(self):
        config=self.base/"config";config.write_text("original")
        result=self.shell('cp() { return 86; }; replace_config "$1" "replacement"',config,ok=False)
        self.assertEqual(result.returncode,86)
        self.assertEqual(config.read_text(),"original")

    def test_global_opt_in_preserves_status_and_file_modes(self):
        global_root=self.base/"global";(global_root/".claude").mkdir(parents=True)
        settings=global_root/".claude/settings.json"
        settings.write_text(json.dumps({"statusLine":{"type":"command","command":"my-status"},"hooks":{}}))
        settings.chmod(0o600)
        bashrc=global_root/".bashrc";bashrc.write_text("# original\n");bashrc.chmod(0o640)
        self.shell('CONFIGURE_GLOBAL=false; phase7_global "$1"',global_root)
        self.assertEqual(list(global_root.rglob("*.bak")),[])
        self.shell('CONFIGURE_GLOBAL=true; phase7_global "$1"',global_root)
        self.assertEqual(json.loads(settings.read_text())["statusLine"]["command"],"my-status")
        self.assertEqual(stat.S_IMODE(settings.stat().st_mode),0o600)
        self.assertEqual(stat.S_IMODE(bashrc.stat().st_mode),0o640)
        backups=list(global_root.rglob("*.bak"));self.assertEqual(len(backups),2)
        self.shell('CONFIGURE_GLOBAL=true; phase7_global "$1"',global_root)
        self.assertEqual(len(list(global_root.rglob("*.bak"))),2)
        self.shell('TEST_MODE=true; CONFIGURE_GLOBAL=true; phase7_global "$1"',global_root)
        self.assertEqual(len(list(global_root.rglob("*.bak"))),2)

    def test_launcher_failure_preserves_old_command(self):
        fake=self.base/"app";fake.mkdir()
        (fake/"bootstrap.sh").write_text("#!/bin/bash\nexit 23\n")
        (fake/"bootstrap.sh").chmod(0o755)
        bin_dir=self.base/"bin";bin_dir.mkdir()
        old=bin_dir/"mkproj";old.write_text("old launcher\n");old.chmod(0o750)
        result=command("bash","-c",
            'set -euo pipefail; source "$1/install.sh"; BOOTSTRAP_DIR="$2"; BIN_DIR="$3"; LAUNCHER="$BIN_DIR/mkproj"; install_launcher',
            "test",ROOT,fake,bin_dir,ok=False)
        self.assertNotEqual(result.returncode,0)
        self.assertEqual(old.read_text(),"old launcher\n")
        self.assertEqual(stat.S_IMODE(old.stat().st_mode),0o750)
        self.assertEqual(list(bin_dir.glob(".mkproj-launcher.*")),[])

    def test_launcher_quoted_paths_backups_and_legacy_alias(self):
        fake=self.base/"app's space";fake.mkdir()
        (fake/"bootstrap.sh").write_text("#!/bin/bash\n[[ \"$1\" == --help ]]\n")
        (fake/"bootstrap.sh").chmod(0o755)
        bin_dir=self.base/"bin";bin_dir.mkdir()
        old=bin_dir/"mkproj";old.write_text("old launcher\n");old.chmod(0o750)
        legacy=bin_dir/"proj";legacy.write_text("legacy\n")
        command("bash","-c",
            'set -euo pipefail; source "$1/install.sh"; BOOTSTRAP_DIR="$2"; BIN_DIR="$3"; LAUNCHER="$BIN_DIR/mkproj"; install_launcher',
            "test",ROOT,fake,bin_dir)
        command(old,"--help")
        self.assertEqual(legacy.read_text(),"legacy\n")
        backups=list((bin_dir/"backups").glob("mkproj.*.bak"))
        self.assertEqual(len(backups),1)
        self.assertEqual(backups[0].read_text(),"old launcher\n")
        self.assertEqual(stat.S_IMODE(backups[0].stat().st_mode),0o750)

    def test_archive_collisions_no_duplicates_and_missing_query_failure(self):
        project=self.base/"project";project.mkdir()
        command(REAL_PYTHON,"-m","venv",project/".venv")
        hook=ROOT/"templates/hooks/save-response.sh"
        for text in ["first","second","third","third"]:
            command("bash",hook,env={"CLAUDE_PROJECT_DIR":str(project)},
                    data=json.dumps({"prompt":"question","last_assistant_message":text}))
        files=sorted((project/"responses").glob("*.txt"))
        self.assertEqual(len(files),3)
        self.assertEqual(len({p.read_text() for p in files}),3)
        self.assertTrue(all(stat.S_IMODE(p.stat().st_mode)==0o600 for p in files))
        marker=project/"responses/.last-saved"
        self.assertIn("third",Path(marker.read_text().strip()).read_text())
        result=command("bash",hook,env={"CLAUDE_PROJECT_DIR":str(project)},
                       data=json.dumps({"last_assistant_message":"no query"}),ok=False)
        self.assertNotEqual(result.returncode,0)
        self.assertEqual(len(list((project/"responses").glob("*.txt"))),3)

    def test_doctor_is_read_only_and_reports_missing_venv(self):
        repo=fixture_repo(self.base/"project")
        shutil.copy(ROOT/"templates/.gitignore",repo/".gitignore")
        before=snapshot(repo/".git/config")
        result=command("bash",ROOT/"bootstrap.sh","--doctor",cwd=repo,ok=False)
        self.assertNotEqual(result.returncode,0)
        self.assertIn("venv interpreter missing",result.stderr)
        self.assertEqual(snapshot(repo/".git/config"),before)
        self.assertFalse((repo/".venv").exists())


    def test_generated_commit_leaves_existing_user_files_untracked(self):
        project=self.base/"sample";project.mkdir()
        (project/"README.md").write_text("user readme\n")
        (project/"notes.txt").write_text("user notes\n")
        command("bash",ROOT/"bootstrap.sh","--agent=none","--no-global","sample",
                cwd=self.base,data="y\nn\ny\n")
        self.assertEqual((project/"README.md").read_text(),"user readme\n")
        tracked=git(project,"ls-files").stdout.splitlines()
        self.assertNotIn("notes.txt",tracked)
        self.assertNotIn("README.md",tracked)
        self.assertNotIn("responses/.gitkeep",tracked)

    def test_existing_native_hooks_and_hookspath_are_preserved(self):
        for kind in ["native","path","custom"]:
            repo=fixture_repo(self.base/kind)
            if kind=="native":
                (repo/".git/hooks/pre-commit").write_text("user hook\n")
            elif kind=="path":
                git(repo,"config","core.hooksPath","custom-hooks")
            else:
                (repo/".githooks").mkdir()
                (repo/".githooks/pre-commit").write_text("user hook\n")
            before=(repo/".git/config").read_bytes()
            result=self.shell('PROJECT_DIR="$1"; configure_git_guards',repo,ok=False)
            self.assertNotEqual(result.returncode,0)
            self.assertEqual((repo/".git/config").read_bytes(),before)

    def test_concurrent_project_lock_refuses_before_mutation(self):
        import fcntl
        project=self.base/"sample"
        lock_dir=Path("/tmp")/f"mkproj-locks-{os.getuid()}"
        lock_dir.mkdir(mode=0o700,exist_ok=True)
        key=hashlib.sha256(str(project).encode()).hexdigest()
        with (lock_dir/key).open("w") as stream:
            fcntl.flock(stream,fcntl.LOCK_EX|fcntl.LOCK_NB)
            result=command("bash",ROOT/"bootstrap.sh","--agent=none","--no-global","sample",
                           cwd=self.base,data="y\nn\ny\n",ok=False)
            self.assertNotEqual(result.returncode,0)
            self.assertIn("Another mkproj instance",result.stderr)
            self.assertFalse(project.exists())

    def test_wrong_project_venv_is_rejected_before_install(self):
        project=self.base/"sample";project.mkdir()
        git(project,"init","-q","-b","main")
        shutil.copy(ROOT/"templates/.gitignore",project/".gitignore")
        shutil.copy(ROOT/"templates/.gitattributes",project/".gitattributes")
        for name in ["CLAUDE.md","AGENTS.md"]:(project/name).write_text("fixture")
        (project/".claude").mkdir()
        (project/".claude/settings.json").write_text("{}")
        (project/".venv/bin").mkdir(parents=True)
        (project/".venv/bin/python").symlink_to(REAL_PYTHON)
        result=self.shell('PROJECT_DIR="$1"; phase9_verify',project,ok=False)
        self.assertNotEqual(result.returncode,0)
        self.assertFalse((project/".env").exists())

    def test_agent_launch_choice_and_missing_agent(self):
        project=self.base/"project";project.mkdir()
        wrapper=self.base/"bin";wrapper.mkdir()
        marker=self.base/"agent"
        (wrapper/"codex").write_text("#!/bin/bash\nprintf '%s' \"$PWD\" > "+str(marker)+"\n")
        (wrapper/"codex").chmod(0o755)
        self.shell('PROJECT_DIR="$1"; LAUNCH_AGENT=codex; launch_agent',project,
                   env={"PATH":str(wrapper)+":"+os.environ["PATH"]})
        self.assertEqual(marker.read_text(),str(project))
        marker.unlink()
        self.shell('PROJECT_DIR="$1"; LAUNCH_AGENT=none; launch_agent',project)
        self.assertFalse(marker.exists())
        # No global setup runs during agent selection or launch.
        self.assertFalse((project/".claude").exists())



    def test_legacy_auto_venv_upgrades_with_backup(self):
        global_root=self.base/"global";global_root.mkdir()
        bashrc=global_root/".bashrc"
        bashrc.write_text("""# auto-venv cd override
cd() {
    builtin cd "$@"
    if [[ -f ".venv/bin/activate" && -z "${VIRTUAL_ENV:-}" ]]; then
        source .venv/bin/activate
    fi
}
""")
        original=bashrc.read_text()
        self.shell('CONFIGURE_GLOBAL=true; phase7_global "$1"',global_root)
        self.assertIn("MKPROJ_AUTO_VENV",bashrc.read_text())
        backups=list((global_root/"backups").glob(".bashrc.*.bak"))
        self.assertEqual(len(backups),1)
        self.assertEqual(backups[0].read_text(),original)

    def test_auto_venv_switches_only_managed_environments_and_failed_cd_is_safe(self):
        first=self.base/"first";second=self.base/"second";empty=self.base/"empty"
        for path in [first,second,empty]:path.mkdir()
        for path in [first,second]:
            command(REAL_PYTHON,"-m","venv",path/".venv")
        config=self.base/"global";config.mkdir()
        self.shell('CONFIGURE_GLOBAL=true; phase7_global "$1"',config)
        command("bash","-c",
            'set -uo pipefail; source "$1/.bashrc" || exit 11; unset VIRTUAL_ENV MKPROJ_AUTO_VENV; '
            'cd "$2" || exit 12; [[ "${VIRTUAL_ENV:-}" == "$2/.venv" ]] || { printf "Venv path mismatch: actual=%s expected=%s\\n" "${VIRTUAL_ENV:-unset}" "$2/.venv" >&2; exit 13; }; '
            'cd "$3" || exit 14; [[ "${VIRTUAL_ENV:-}" == "$3/.venv" ]] || exit 15; '
            'if cd "$3/nonexistent" 2>/dev/null; then exit 16; fi; '
            '[[ "${VIRTUAL_ENV:-}" == "$3/.venv" ]] || exit 17; '
            'cd "$4" || exit 18; [[ -z "${VIRTUAL_ENV:-}" ]] || exit 19',
            "test",config,first,second,empty,
            env={"VIRTUAL_ENV":None,"MKPROJ_AUTO_VENV":None})

    def test_doctor_detects_tracked_private_paths(self):
        repo=fixture_repo(self.base/"project")
        shutil.copy(ROOT/"templates/.gitignore",repo/".gitignore")
        (repo/"secrets").mkdir();(repo/"secrets/private.txt").write_text("private")
        git(repo,"add","-f","secrets/private.txt")
        result=self.shell('PROJECT_DIR="$1"; verify_privacy_rules',repo,ok=False)
        self.assertNotEqual(result.returncode,0)
        self.assertIn("Private path is already tracked",result.stderr)


if __name__=="__main__":
    unittest.main()

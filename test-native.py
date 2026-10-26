#!/usr/bin/env python3
"""Run the repository's Yazi config in a disposable native PTY (Unix only)."""
import argparse
import re
import fcntl
import json
import os
from pathlib import Path
import pty
import select
import shutil
import signal
import struct
import subprocess
import tempfile
import termios
import time


PROBE = r'''--- @sync entry
return { entry = function()
  local ok, result = pcall(function()
    local git = require("dots.git")
    local projects, head = require("dots.projects"), require("dots.githead")
    local dirs = 0
    for _ in pairs(git.dirs) do dirs = dirs + 1 end
    local colors = require("dots.ls-colors")
    if not require("probe").colors_checked then
      local file = cx.active.current.hovered
      if file then
        colors:setup({ enabled = false })
        local expected = file:style() or ui.Style()
        local actual = colors:style(file):raw()
        for key, value in pairs(expected:raw()) do assert(actual[key] == value, "fallback style mismatch") end
        colors:setup({ enabled = true })
        require("probe").colors_checked = true
      end
    end
    local function collect(folder)
      local styles = {}
      if not folder then return styles end
      for _, file in ipairs(folder.files) do
        local entity = Entity:new(file)
        local cap = entity:style_rev()
        styles[file.name] = {
          cap = cap and cap:raw() or false, padding_plain = entity:padding() == " ",
          base = colors:style(file):raw(), target = colors:target_style(file):raw(), row = Entity:new(file):style():raw(),
          hovered = file.is_hovered, is_link = file.link_to ~= nil,
          indicator = (file.in_current and th.indicator.current or file.in_preview and th.indicator.preview or th.indicator.parent):raw(),
        }
      end
      return styles
    end
    local file_styles = collect(cx.active.current)
    if not require("probe").hover_checked and cx.active.current.hovered then
      local original = Dotline.coloreds.get.hover
      local hover = require("dots.hover")
      hover:setup({ auto_fit = false, styles = {
        name = { source = "file", fg = "#abcdef", bg = "reset", bold = false, italic = true },
        icon = { source = "name", fg = 123, reversed = true },
      } })
      local custom = {}
      for _, span in ipairs(Dotline.coloreds.get:hover()) do custom[span.part] = span.style:raw() end
      assert(custom.name.fg == "#ABCDEF" and custom.name.bg == "Reset" and not custom.name.bold and custom.name.italic)
      assert(not custom.name.reversed, "icon override leaked into name")
      if custom.icon then assert(custom.icon.fg == "123" and custom.icon.reversed and custom.icon.italic) end
      colors:setup({ enabled = false })
      hover:setup({ auto_fit = false })
      local fallback = {}
      for _, span in ipairs(Dotline.coloreds.get:hover()) do fallback[span.part] = span.style:raw() end
      local native = cx.active.current.hovered:style()
      if native then
        for key, value in pairs(native:raw()) do
          assert(fallback.name[key] == value, "hover native fallback mismatch")
        end
      end
      colors:setup({ enabled = true })
      Dotline.coloreds.get.hover = original
      require("probe").hover_checked = true
    end
    local spans = Dotline.coloreds.get:hover() or {}
    local header_styles = {}
    for _, span in ipairs(spans) do
      if span.part then header_styles[span.part] = span.style:raw() end
    end
    local hovered_style, target_style = header_styles.name, header_styles.link
    local repo_span = (Dotline.coloreds.get:repo_name() or {})[1] or {}
    return {
      file_styles = file_styles, hovered_style = hovered_style, target_style = target_style, header_styles = header_styles,
      pane_styles = { collect(cx.active.parent), collect(cx.active.preview.folder) },
      cwd = tostring(cx.active.current.cwd),
      ratio = { rt.mgr.ratio[1], rt.mgr.ratio[2], rt.mgr.ratio[3] },
      sort = cx.active.pref.sort_by, reverse = cx.active.pref.sort_reverse,
      dirs_first = cx.active.pref.sort_dir_first,
      repo = head.name or "", branch = head.output and head.output.branch or "",
      repo_label = repo_span[1] or "", repo_color = repo_span[2] or "",
      git_dirs = dirs, projects = #projects.projects.list,
      project_name = projects.projects.list[1] and projects.projects.list[1].desc or "",
      dotline = Dotline ~= nil, yatline = Yatline ~= nil,
      githead_id = head._id, projects_id = projects._id,
      merged = require("probe").merged or 0,
    }
  end)
  local f = assert(io.open(os.getenv("HOME") .. "/probe.jsonl", "a"))
  f:write(require("dots.json").encode(ok and result or { error = tostring(result) }), "\n")
  f:close()
end, setup = function(self)
  ps.sub_remote("project-merged", function() self.merged = (self.merged or 0) + 1 end)
end }
'''


def run():
    plugin = Path(__file__).resolve().parent
    parser = argparse.ArgumentParser()
    parser.add_argument('--config-dir', type=Path, default=plugin / 'tests/fixtures/config')
    config = parser.parse_args().config_dir.resolve()
    source_config = (config / 'init.lua').read_text()
    def option(name, default):
        found = re.search(r'\b' + name + r'\s*=\s*"([^"]+)"', source_config)
        if found:
            return found.group(1)
        ref = re.search(r'\b' + name + r'\s*=\s*dots\.colors\.git\.(repo_owned|repo)\b', source_config)
        return {'repo':'magenta','repo_owned':'yellow'}[ref.group(1)] if ref else default
    repo_color, owned_color = option('repo_color', 'blue'), option('repo_owned_color', 'blue')
    with tempfile.TemporaryDirectory(prefix="dots-yazi-test-") as temporary:
        root = Path(temporary)
        for name in ("home", "config", "state", "cache", "data", "runtime", "tmp", "work", "outside"):
            (root / name).mkdir()
        cfg = root / "config"
        shutil.copytree(plugin, cfg / "plugins/dots.yazi", ignore=shutil.ignore_patterns(".git", ".codex", ".agents", "tests"))
        for name in ("init.lua", "keymap.toml", "yazi.toml"):
            shutil.copyfile(config / name, cfg / name)
        (cfg / "theme.toml").write_text('[indicator]\npadding = { open = "█", close = "█" }\npreview = { underline = true }\n')
        probe = cfg / "plugins/probe.yazi"
        probe.mkdir()
        (probe / "main.lua").write_text(PROBE)
        with (cfg / "init.lua").open("a") as file:
            file.write('\nrequire("probe"):setup()\n')
        with (cfg / "keymap.toml").open("a") as file:
            file.write('\n[[mgr.prepend_keymap]]\non = "~"\nrun = "plugin probe"\n')
            file.write('\n[[mgr.prepend_keymap]]\non = "!"\nrun = "plugin dots -- projects load a"\n')
            file.write('\n[[mgr.prepend_keymap]]\non = "@"\nrun = "plugin dots -- projects delete a"\n')
            for key, target in (("1", root / "outside/Downloads"), ("2", root / "outside"), ("3", root / "work")):
                file.write('\n[[mgr.prepend_keymap]]\non = ' + json.dumps(key) + '\nrun = ' + json.dumps("cd " + str(target)) + '\n')
        (root / "outside/Downloads").mkdir()
        env = os.environ.copy()
        for name in ("TMUX", "TMUX_PANE", "YAZI_ID", "YAZI_LEVEL", "APPDATA", "LOCALAPPDATA", "GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE"):
            env.pop(name, None)
        env.update(
            HOME=str(root / "home"), XDG_CONFIG_HOME=str(root / "config-root"),
            YAZI_CONFIG_HOME=str(cfg), XDG_STATE_HOME=str(root / "state"),
            XDG_CACHE_HOME=str(root / "cache"), XDG_DATA_HOME=str(root / "data"),
            XDG_RUNTIME_DIR=str(root / "runtime"), TMPDIR=str(root / "tmp"),
            YAZI_LOG="debug", TERM="xterm-256color", GIT_CONFIG_NOSYSTEM="1",
            GIT_CONFIG_GLOBAL=os.devnull,
            LS_COLORS="di=1;34:ln=4;38;2;12;34;56;48;2;65;43;21:*.txt=1;38;5;123;48;5;234",
        )
        def git(*args):
            return subprocess.run(["git", *args], cwd=root / "work", env=env, check=True, capture_output=True)
        git("init", "-b", "fixture")
        helper_config = root / "config-root/git-it/config"
        helper_config.parent.mkdir(parents=True)
        helper_config.write_text('[git-it]\nowner = github.com/fixture-owner\n'
                                 'owner = gitlab.com/team/subgroup\nhostAlias = github-fixture=github.com\n')
        git("remote", "add", "origin", "https://github.com/fixture-owner/work.git")
        (root / "work/tracked.txt").write_text("initial\n")
        git("add", "tracked.txt")
        git("-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid", "commit", "-m", "fixture")
        (root / "work/tracked.txt").write_text("modified\n")
        (root / "work/-space 路径.txt").write_text("untracked\n")
        (root / "work/link").symlink_to(root / "work/-space 路径.txt")
        master, slave = pty.openpty()
        fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 30, 120, 0, 0))
        def session():
            os.setsid()
            fcntl.ioctl(0, termios.TIOCSCTTY, 0)
        process = subprocess.Popen(["yazi", str(root / "work")], stdin=slave, stdout=slave, stderr=slave,
                                   env=env, cwd=root / "work", preexec_fn=session)
        os.close(slave)
        output = bytearray()
        def pump(seconds=0.25):
            deadline = time.monotonic() + seconds
            while time.monotonic() < deadline:
                if select.select([master], [], [], 0.05)[0]:
                    try:
                        data = os.read(master, 65536)
                    except OSError:
                        break
                    output.extend(data)
                    if b"\x1b[6n" in data:
                        os.write(master, b"\x1b[1;1R")
                    if b"\x1b[0c" in data or b"\x1b[c" in data:
                        os.write(master, b"\x1b[?1;2c")
                    if b"\x1b]11;?" in data:
                        os.write(master, b"\x1b]11;rgb:0000/0000/0000\x1b\\")
        def key(value):
            os.write(master, value)
            pump()
        result_file = root / "home/probe.jsonl"
        def snapshot():
            before = len(result_file.read_text().splitlines()) if result_file.exists() else 0
            key(b"~")
            deadline = time.monotonic() + 3
            while time.monotonic() < deadline:
                rows = result_file.read_text().splitlines() if result_file.exists() else []
                if len(rows) > before:
                    result = json.loads(rows[-1])
                    assert "error" not in result, result
                    return result
                pump()
            raise AssertionError("probe did not respond")
        def wait_for(predicate):
            deadline = time.monotonic() + 5
            while time.monotonic() < deadline:
                state = snapshot()
                if predicate(state):
                    return state
                pump()
            raise AssertionError(state)
        try:
            pump(2)
            state = wait_for(lambda s: s["repo"] == "work" and s["branch"] == "fixture" and s["git_dirs"] > 0)
            assert state["dotline"] and not state["yatline"], state
            assert state["githead_id"] == "dots.githead" and state["projects_id"] == "dots.projects", state
            assert state["repo_label"] == "󰊤 work" and state["repo_color"] == owned_color, state
            styles = state["file_styles"]
            def active_style(style):
                return {key: value for key, value in style.items() if value is not False}
            assert active_style(styles["tracked.txt"]["base"]) == {"fg": "123", "bg": "234", "bold": True}, styles
            assert active_style(styles["link"]["base"]) == {"fg": "#0C2238", "bg": "#412B15", "underline": True}, styles
            assert styles["link"]["target"] == styles["tracked.txt"]["base"], styles
            cap_checks = set()
            def check_cap(value, pane):
                if not value["hovered"]:
                    return
                row = value["row"]
                if row.get("bg") == "Reset" and not row.get("reversed"):
                    assert value["cap"] is False and value["padding_plain"], value
                    cap_checks.add(pane + "-plain")
                else:
                    assert value["cap"] is not False, value
                    background = row.get("fg") if row.get("reversed") else row.get("bg")
                    assert value["cap"]["fg"] == background, value
                    cap_checks.add(pane + "-filled")
            def check_styles(state):
                for value in state["file_styles"].values():
                    check_cap(value, "current")
                    if value["hovered"]:
                        assert state["hovered_style"] == value["base"], state
                        if "icon" in state["header_styles"]:
                            assert state["header_styles"]["icon"] == state["hovered_style"], state
                        if value["is_link"]:
                            assert state["target_style"] == value["target"], state
                            assert active_style(state["header_styles"]["link_dir"]) == {"fg": "Blue", "bg": "Reset", "bold": True}, state
                        expected = dict(value["base"], **value["indicator"])
                        assert value["row"] == expected, (value, expected)
                    else:
                        assert value["row"] == value["base"], value
                for index, pane in enumerate(state["pane_styles"]):
                    for value in (pane.values() if isinstance(pane, dict) else []):
                        check_cap(value, "parent" if index == 0 else "preview")
                        expected = dict(value["base"])
                        if value["hovered"]:
                            expected.update(value["indicator"])
                        assert value["row"] == expected, value
            check_styles(state)
            assert active_style(state["header_styles"]["path"]) == {"fg": "Blue", "bg": "Reset", "bold": True}, state["header_styles"]
            for _ in range(len(styles)):
                key(b"j")
                check_styles(snapshot())
            assert "preview-plain" in cap_checks and "current-filled" in cap_checks, cap_checks
            print("PASS native separate symlink/target styles, preview spacing and filled cursor caps", flush=True)
            original_ratio = snapshot()["ratio"]
            hidden_ratio = original_ratio[:2] + [0]
            maximum_ratio = original_ratio[:2] + [9999]
            for action, ratio in ((b"\x18", hidden_ratio), (b"\x18", original_ratio), (b"X", maximum_ratio), (b"X", original_ratio)):
                key(action)
                assert snapshot()["ratio"] == ratio
            print("PASS native startup, module state, Git callbacks/fetcher, pane shortcuts", flush=True)
            # Remote changes are local metadata only; refresh through normal cd callbacks.
            for remote, icon, color in (
                ("git@github.com:someone-else/work.git", "󰊤", repo_color),
                ("ssh://git@github-fixture/fixture-owner/work.git", "󰊤", owned_color),
                ("https://gitlab.com/team/subgroup/work.git", "", owned_color),
                ("https://bitbucket.org/fixture-owner/work.git", "", repo_color),
                ("https://unknown.example/fixture-owner/work.git", "", repo_color),
                (None, "", repo_color),
            ):
                if remote is None:
                    git("remote", "remove", "origin")
                else:
                    git("remote", "set-url", "origin", remote)
                key(b"2")
                state = wait_for(lambda s: s["cwd"] == str(root / "outside"))
                assert state["repo_label"] == "", state
                key(b"3")
                state = wait_for(lambda s: s["repo_label"] == icon + " work" and s["repo_color"] == color)
                assert state["branch"] == "fixture", state
            print("PASS native git-it host icons, ownership colors, aliases, nested namespaces and no-remote fallback", flush=True)
            key(b"Ps"); key(b"a"); key(b"\x15"); key(b"Fixture project\r")
            state = wait_for(lambda s: s["projects"] == 1)
            assert state["project_name"] == "Fixture project", state
            key(b"1")
            state = wait_for(lambda s: s["cwd"].endswith("/Downloads"))
            assert state["sort"] == "mtime" and state["reverse"] and not state["dirs_first"], state
            key(b"2")
            state = wait_for(lambda s: s["cwd"] == str(root / "outside"))
            assert state["sort"] == "alphabetical" and not state["reverse"] and state["dirs_first"], state
            assert state["repo"] == "", state
            key(b"PP")
            wait_for(lambda s: s["cwd"] == str(root / "work"))
            key(b"2"); key(b"!")
            wait_for(lambda s: s["cwd"] == str(root / "work"))
            # Current and all-tab merge actions must deliver their events.
            key(b"Pm"); key(b"PM")
            wait_for(lambda s: s["merged"] == 2)
            key(b"@")
            wait_for(lambda s: s["projects"] == 0)
            key(b"Ps"); key(b"a"); key(b"\r")
            wait_for(lambda s: s["projects"] == 1)
            key(b"PD")
            wait_for(lambda s: s["projects"] == 0)
            print("PASS native project save/load/last/delete/delete-all, merge event dispatch and folder rules", flush=True)
            for width in (40, 80, 160):
                fcntl.ioctl(master, termios.TIOCSWINSZ, struct.pack("HHHH", 30, width, 0, 0))
                os.kill(process.pid, signal.SIGWINCH)
                pump()
                resized = snapshot()
                assert resized["dotline"]
                check_styles(resized)
            key(b"q"); pump(0.5)
            assert process.poll() == 0, process.poll()
            log = root / "state/yazi/yazi.log"
            logs = log.read_text() if log.exists() else ""
            assert "ERROR" not in logs, logs[:4000]
            assert b"deprecated" not in output, output[-1000:]
            assert b"Failed to" not in output and b"runtime error" not in output, output[-3000:]
            print("PASS native 40/80/160-column redraw, clean exit and error log", flush=True)
        except BaseException:
            log = root / "state/yazi/yazi.log"
            print(log.read_text()[:4000] if log.exists() else "No log")
            print(repr(output[-2500:]))
            raise
        finally:
            if process.poll() is None:
                process.kill()
                process.wait(timeout=3)
            os.close(master)


if __name__ == "__main__":
    run()

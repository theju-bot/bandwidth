#!/usr/bin/env python3
import os
import sys
import json
import time
import re
import shutil
import subprocess
from datetime import date
from pathlib import Path

STATE_DIR = Path.home() / ".local/state/omarchy/theju-bot.bandwidth"
LEGACY_DIR = Path.home() / ".local/state/omarchy/bandwhich-usage"

if not STATE_DIR.exists() and LEGACY_DIR.exists():
    try:
        shutil.copytree(LEGACY_DIR, STATE_DIR)
    except Exception:
        pass

STATE_FILE = STATE_DIR / "stats.json"
CONFIG_FILE = STATE_DIR / "config.json"

def load_config():
    if CONFIG_FILE.exists():
        try:
            with open(CONFIG_FILE, "r", encoding="utf-8") as f:
                return json.load(f)
        except Exception:
            pass
    return {}

def save_config(cfg):
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    tmp_file = CONFIG_FILE.with_suffix(".tmp")
    try:
        with open(tmp_file, "w", encoding="utf-8") as f:
            json.dump(cfg, f)
        os.replace(tmp_file, CONFIG_FILE)
    except Exception as e:
        sys.stderr.write(f"Error saving config: {e}\n")

LINE_REGEX = re.compile(r'process:\s+<\d+>\s+"([^"]+)"\s+up/down\s+Bps:\s+(\d+)/(\d+)')

def get_today_str():
    return date.today().isoformat()

def load_state():
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    today = get_today_str()
    if STATE_FILE.exists():
        try:
            with open(STATE_FILE, "r", encoding="utf-8") as f:
                data = json.load(f)
                file_date = data.get("date", today)
                history = data.get("history", {})

                if file_date != today:
                    # Archive previous day if it had traffic
                    prev_down = data.get("today_down", 0)
                    prev_up = data.get("today_up", 0)
                    if prev_down > 0 or prev_up > 0:
                        history[file_date] = {
                            "down": prev_down,
                            "up": prev_up,
                            "total": prev_down + prev_up
                        }

                    # Prune history to 30 days
                    sorted_dates = sorted(history.keys(), reverse=True)
                    if len(sorted_dates) > 30:
                        history = {d: history[d] for d in sorted_dates[:30]}

                    data = {
                        "date": today,
                        "today_down": 0,
                        "today_up": 0,
                        "apps": {},
                        "history": history,
                        "status": data.get("status", "ok")
                    }
                else:
                    if "history" not in data:
                        data["history"] = {}
                return data
        except Exception:
            pass

    return {
        "date": today,
        "today_down": 0,
        "today_up": 0,
        "apps": {},
        "history": {},
        "status": "ok"
    }

def save_state(state):
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    tmp_file = STATE_FILE.with_suffix(".tmp")
    try:
        with open(tmp_file, "w", encoding="utf-8") as f:
            json.dump(state, f)
        os.replace(tmp_file, STATE_FILE)
    except Exception as e:
        sys.stderr.write(f"Error saving state: {e}\n")

def check_bandwhich():
    bandwhich_path = shutil.which("bandwhich")
    if not bandwhich_path:
        return False, "bandwhich is not installed. Please install it (e.g. pacman -S bandwhich)."

    try:
        proc = subprocess.run(
            [bandwhich_path, "--raw", "-p"],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=0.6
        )
        if proc.returncode != 0 and "Insufficient permissions" in proc.stderr:
            return False, "Insufficient permissions. Run: sudo setcap 'cap_sys_ptrace,cap_dac_read_search,cap_net_raw,cap_net_admin+ep' /usr/bin/bandwhich"
    except subprocess.TimeoutExpired:
        return True, ""
    except Exception as e:
        return False, str(e)

    return True, ""

def run_daemon():
    bandwhich_bin = shutil.which("bandwhich") or "/usr/bin/bandwhich"
    ok, err_msg = check_bandwhich()
    if not ok:
        state = load_state()
        state["status"] = "error"
        state["error"] = err_msg
        save_state(state)
        sys.stderr.write(f"{err_msg}\n")
        while True:
            time.sleep(5)
            ok, err_msg = check_bandwhich()
            if ok:
                break
            state["error"] = err_msg
            save_state(state)

    state = load_state()
    state["status"] = "ok"
    if "error" in state:
        del state["error"]

    while True:
        try:
            proc = subprocess.Popen(
                [bandwhich_bin, "--raw", "--processes", "-u", "bin-bytes"],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                bufsize=1
            )
        except Exception as e:
            state["status"] = "error"
            state["error"] = str(e)
            save_state(state)
            time.sleep(5)
            continue

        last_write = time.time()
        has_new_data = False

        for line in proc.stdout:
            current_today = get_today_str()
            if state.get("date") != current_today:
                # Archive yesterday into history
                prev_date = state.get("date", current_today)
                prev_down = state.get("today_down", 0)
                prev_up = state.get("today_up", 0)
                history = state.get("history", {})
                if prev_down > 0 or prev_up > 0:
                    history[prev_date] = {
                        "down": prev_down,
                        "up": prev_up,
                        "total": prev_down + prev_up
                    }

                state = {
                    "date": current_today,
                    "today_down": 0,
                    "today_up": 0,
                    "apps": {},
                    "history": history,
                    "status": "ok"
                }
                has_new_data = True

            match = LINE_REGEX.match(line.strip())
            if match:
                app_name = match.group(1)
                up_bytes = int(match.group(2))
                down_bytes = int(match.group(3))

                if up_bytes > 0 or down_bytes > 0:
                    state["today_up"] += up_bytes
                    state["today_down"] += down_bytes
                    app_record = state["apps"].setdefault(app_name, {"down": 0, "up": 0})
                    app_record["down"] += down_bytes
                    app_record["up"] += up_bytes
                    has_new_data = True

            now = time.time()
            if has_new_data and (now - last_write >= 1.0):
                save_state(state)
                last_write = now
                has_new_data = False

        stderr_output = proc.stderr.read() if proc.stderr else ""
        if "Insufficient permissions" in stderr_output:
            state["status"] = "error"
            state["error"] = "Insufficient permissions. Run: sudo setcap 'cap_sys_ptrace,cap_dac_read_search,cap_net_raw,cap_net_admin+ep' /usr/bin/bandwhich"
            save_state(state)

        time.sleep(2)

def run_status():
    state = load_state()
    today_down = state.get("today_down", 0)
    today_up = state.get("today_up", 0)
    today_date = state.get("date", get_today_str())

    # Build apps list
    apps_raw = state.get("apps", {})
    all_apps = []
    for name, stats in apps_raw.items():
        d = stats.get("down", 0)
        u = stats.get("up", 0)
        all_apps.append({
            "name": name,
            "down": d,
            "up": u,
            "total": d + u
        })

    # Top downloads (sorted down descending, only apps with down > 0)
    top_downloads = [a for a in all_apps if a["down"] > 0]
    top_downloads.sort(key=lambda x: x["down"], reverse=True)

    # Top uploads (sorted up descending, only apps with up > 0)
    top_uploads = [a for a in all_apps if a["up"] > 0]
    top_uploads.sort(key=lambda x: x["up"], reverse=True)

    # Daily history
    history = state.get("history", {})
    days = []
    # Add today
    days.append({
        "date": today_date,
        "down": today_down,
        "up": today_up,
        "total": today_down + today_up,
        "is_today": True
    })
    # Add historical days sorted descending
    for d_str in sorted(history.keys(), reverse=True):
        if d_str == today_date:
            continue
        rec = history[d_str]
        d_val = rec.get("down", 0)
        u_val = rec.get("up", 0)
        days.append({
            "date": d_str,
            "down": d_val,
            "up": u_val,
            "total": d_val + u_val,
            "is_today": False
        })

    cfg = load_config()
    result = {
        "date": today_date,
        "today_down": today_down,
        "today_up": today_up,
        "total": today_down + today_up,
        "status": state.get("status", "ok"),
        "error": state.get("error", ""),
        "top_downloads": top_downloads[:10],
        "top_uploads": top_uploads[:10],
        "minimalistic": cfg.get("minimalistic", False),
        "days": days[:14]
    }
    print(json.dumps(result))

if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "daemon":
        run_daemon()
    elif len(sys.argv) > 1 and sys.argv[1] == "set-minimal":
        val = sys.argv[2].lower() in ("true", "1", "yes") if len(sys.argv) > 2 else False
        cfg = load_config()
        cfg["minimalistic"] = val
        save_config(cfg)
    else:
        run_status()

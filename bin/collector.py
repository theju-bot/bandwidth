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
                    prev_down = data.get("today_down", 0)
                    prev_up = data.get("today_up", 0)
                    if prev_down > 0 or prev_up > 0:
                        history[file_date] = {
                            "down": prev_down,
                            "up": prev_up,
                            "total": prev_down + prev_up
                        }

                    sorted_dates = sorted(history.keys(), reverse=True)
                    if len(sorted_dates) > 30:
                        history = {d: history[d] for d in sorted_dates[:30]}

                    data = {
                        "date": today,
                        "today_down": 0,
                        "today_up": 0,
                        "apps": {},
                        "history": history,
                        "status": data.get("status", "ok"),
                        "current_up_bps": 0,
                        "current_down_bps": 0,
                        "current_rates": {}
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
        "status": "ok",
        "current_up_bps": 0,
        "current_down_bps": 0,
        "current_rates": {}
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
        return False, "not_installed", "bandwhich is not installed. Please install it (e.g. sudo pacman -S bandwhich)."

    try:
        proc = subprocess.run(
            [bandwhich_path, "--raw", "-p"],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=0.6
        )
        if proc.returncode != 0 and "Insufficient permissions" in proc.stderr:
            return False, "permission", f"Insufficient permissions. Run: sudo setcap 'cap_sys_ptrace,cap_dac_read_search,cap_net_raw,cap_net_admin+ep' {bandwhich_path}"
    except subprocess.TimeoutExpired:
        return True, "", ""
    except Exception as e:
        return False, "error", str(e)

    return True, "", ""

def run_daemon():
    bandwhich_bin = shutil.which("bandwhich") or "/usr/bin/bandwhich"
    ok, err_type, err_msg = check_bandwhich()
    if not ok:
        state = load_state()
        state["status"] = "error"
        state["error_type"] = err_type
        state["error"] = err_msg
        save_state(state)
        sys.stderr.write(f"{err_msg}\n")
        while True:
            time.sleep(5)
            ok, err_type, err_msg = check_bandwhich()
            if ok:
                break
            state["error_type"] = err_type
            state["error"] = err_msg
            save_state(state)

    state = load_state()
    state["status"] = "ok"
    if "error" in state:
        del state["error"]
    if "error_type" in state:
        del state["error_type"]

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
            state["error_type"] = "error"
            state["error"] = str(e)
            save_state(state)
            time.sleep(5)
            continue

        current_tick_rates = {}

        for line in proc.stdout:
            line_str = line.strip()
            if line_str.startswith("Refreshing:"):
                # End of a 1-second sample tick
                up_bps = sum(r.get("up", 0) for r in current_tick_rates.values())
                down_bps = sum(r.get("down", 0) for r in current_tick_rates.values())

                state["current_up_bps"] = up_bps
                state["current_down_bps"] = down_bps
                state["current_rates"] = current_tick_rates
                state["last_tick_time"] = time.time()

                save_state(state)
                current_tick_rates = {}
                continue

            current_today = get_today_str()
            if state.get("date") != current_today:
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
                    "status": "ok",
                    "current_up_bps": 0,
                    "current_down_bps": 0,
                    "current_rates": {}
                }

            match = LINE_REGEX.match(line_str)
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

                    current_tick_rates[app_name] = {
                        "up": up_bytes,
                        "down": down_bytes
                    }

        stderr_output = proc.stderr.read() if proc.stderr else ""
        if "Insufficient permissions" in stderr_output:
            state["status"] = "error"
            state["error_type"] = "permission"
            state["error"] = "Insufficient permissions. Run: sudo setcap 'cap_sys_ptrace,cap_dac_read_search,cap_net_raw,cap_net_admin+ep' /usr/bin/bandwhich"
            save_state(state)

        time.sleep(2)

def run_status():
    ok, err_type, err_msg = check_bandwhich()
    state = load_state()

    status_val = state.get("status", "ok")
    error_val = state.get("error", "")
    error_type_val = state.get("error_type", "")
    if not ok:
        status_val = "error"
        error_val = err_msg
        error_type_val = err_type

    today_down = state.get("today_down", 0)
    today_up = state.get("today_up", 0)
    today_date = state.get("date", get_today_str())

    # Check if current_rates is fresh (within last 3.5 seconds)
    last_tick = state.get("last_tick_time", 0)
    is_fresh = (time.time() - last_tick) <= 3.5

    current_up_bps = state.get("current_up_bps", 0) if is_fresh else 0
    current_down_bps = state.get("current_down_bps", 0) if is_fresh else 0
    rates_dict = state.get("current_rates", {}) if is_fresh else {}

    # Build active current apps list with speed in Bps
    current_apps = []
    for name, r in rates_dict.items():
        u = r.get("up", 0)
        d = r.get("down", 0)
        tot = u + d
        if tot > 0:
            current_apps.append({
                "name": name,
                "up_bps": u,
                "down_bps": d,
                "total_bps": tot
            })
    current_apps.sort(key=lambda x: x["total_bps"], reverse=True)

    # Build cumulative apps list
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

    # Top downloads (sorted down descending)
    top_downloads = [a for a in all_apps if a["down"] > 0]
    top_downloads.sort(key=lambda x: x["down"], reverse=True)

    # Top uploads (sorted up descending)
    top_uploads = [a for a in all_apps if a["up"] > 0]
    top_uploads.sort(key=lambda x: x["up"], reverse=True)

    # Daily history
    history = state.get("history", {})
    days = []
    days.append({
        "date": today_date,
        "down": today_down,
        "up": today_up,
        "total": today_down + today_up,
        "is_today": True
    })
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

    result = {
        "date": today_date,
        "today_down": today_down,
        "today_up": today_up,
        "total": today_down + today_up,
        "current_down_bps": current_down_bps,
        "current_up_bps": current_up_bps,
        "current_total_bps": current_down_bps + current_up_bps,
        "status": status_val,
        "error": error_val,
        "error_type": error_type_val,
        "overview_apps": all_apps[:20],
        "current_apps": current_apps,
        "top_downloads": top_downloads[:8],
        "top_uploads": top_uploads[:8],
        "days": days[:14]
    }
    print(json.dumps(result))

if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "daemon":
        run_daemon()
    else:
        run_status()

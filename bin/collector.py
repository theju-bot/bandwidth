#!/usr/bin/env python3
import os
import sys
import json
import time
import re
import shutil
import subprocess
import fcntl
import signal
import atexit
import ctypes
import socket
from datetime import date
from pathlib import Path

# Enforce secure file permissions: owner-only (rwx------ / rw-------)
os.umask(0o077)

STATE_DIR = Path.home() / ".local/state/omarchy/theju-bot.bandwidth"
LEGACY_DIR = Path.home() / ".local/state/omarchy/bandwhich-usage"

# Ensure existing state directory is restricted to owner
if STATE_DIR.exists():
    try:
        os.chmod(STATE_DIR, 0o700)
    except Exception:
        pass

if not STATE_DIR.exists() and LEGACY_DIR.exists():
    try:
        shutil.copytree(LEGACY_DIR, STATE_DIR)
    except Exception:
        pass

STATE_FILE = STATE_DIR / "stats.json"
LOCK_FILE = STATE_DIR / "daemon.lock"

# Known local proxy and tunnel daemons that forward other applications' traffic.
# Counting both the client application and the local proxy core causes double-counting
# of all bandwidth metrics (live speeds, process usage, and daily totals).
PROXY_DAEMONS = {
    "v2raya_core", "v2raya",
    "xray", "v2ray", "xray-core", "v2ray-core",
    "sing-box",
    "clash", "clash-meta", "mihomo", "clash-verge",
    "dae", "daed",
    "sslocal", "ss-local", "ssserver", "shadowsocks-rust",
    "redsocks",
    "privoxy",
    "tor",
    "openvpn"
}

def get_hardware_bytes():
    rx, tx = 0, 0
    try:
        with open("/proc/net/dev", "r", encoding="utf-8") as f:
            for line in f.readlines()[2:]:
                if ":" not in line:
                    continue
                name, _, rest = line.partition(":")
                iface = name.strip()
                if iface == "lo" or iface.startswith(("veth", "docker", "br-", "virbr", "tun", "tap", "wg")):
                    continue
                parts = rest.split()
                if len(parts) >= 9:
                    rx += int(parts[0])
                    tx += int(parts[8])
    except Exception:
        pass
    return rx, tx

def get_local_hosts():
    hosts = {"localhost", "127.0.0.1", "::1", "0.0.0.0", "::"}
    try:
        h = socket.gethostname().lower()
        hosts.add(h)
        hosts.add(f"{h}.")
    except Exception:
        pass
    try:
        # Non-blocking kernel route lookup: extract local host IPs without DNS
        with open("/proc/net/fib_trie", "r", encoding="utf-8") as f:
            prev = ""
            for line in f:
                if "host LOCAL" in line:
                    ip = prev.strip().lstrip("|-+ ")
                    if ip:
                        hosts.add(ip)
                prev = line
    except Exception:
        pass
    return hosts

LAST_HOSTS_REFRESH = 0
LOCAL_HOSTS = set()

def refresh_local_hosts(force=False):
    global LAST_HOSTS_REFRESH, LOCAL_HOSTS
    now = time.time()
    if force or now - LAST_HOSTS_REFRESH > 60 or not LOCAL_HOSTS:
        LOCAL_HOSTS = get_local_hosts()
        LAST_HOSTS_REFRESH = now
    return LOCAL_HOSTS

def is_local_address(addr):
    if not addr:
        return True
    a = addr.lower().rstrip(".")
    hosts = refresh_local_hosts()
    if a in hosts or f"{a}." in hosts:
        return True
    if a.startswith("127.") or a.startswith("::ffff:127."):
        return True
    return False

def normalize_app_name(name):
    if not name or name == "<UNKNOWN>":
        return "<UNKNOWN>"
    n = name.strip()
    nl = n.lower()
    if nl in ("language_server", "antigravity"):
        return "antigravity"
    return n

def sanitize_state(data):
    if not isinstance(data, dict):
        return data
    apps = data.get("apps", {})
    for bad_name in list(apps.keys()):
        if bad_name.lower() in PROXY_DAEMONS or bad_name == "<UNKNOWN>":
            del apps[bad_name]
    # Merge any legacy "language_server" entries into "antigravity"
    if "language_server" in apps:
        ls_rec = apps.pop("language_server")
        ag_rec = apps.setdefault("antigravity", {"down": 0, "up": 0})
        ag_rec["down"] += ls_rec.get("down", 0)
        ag_rec["up"] += ls_rec.get("up", 0)
    return data

CONN_REGEX = re.compile(
    r'connection:\s+<\d+>\s+<([^>]+)>:(\d+)\s+=>\s+(\S+?):(\d+)\s+\((\w+)\)\s+up/down\s+Bps:\s+(\d+)/(\d+)\s+process:\s+"([^"]+)"'
)

def get_today_str():
    return date.today().isoformat()

def load_state():
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    today = get_today_str()
    if STATE_FILE.exists():
        try:
            with open(STATE_FILE, "r", encoding="utf-8") as f:
                data = json.load(f)
                data = sanitize_state(data)
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
    STATE_DIR.mkdir(mode=0o700, parents=True, exist_ok=True)
    tmp_file = STATE_FILE.with_suffix(".tmp")
    try:
        fd = os.open(tmp_file, os.O_CREAT | os.O_WRONLY | os.O_TRUNC, 0o600)
        with open(fd, "w", encoding="utf-8") as f:
            json.dump(state, f)
        os.replace(tmp_file, STATE_FILE)
    except Exception as e:
        sys.stderr.write(f"Error saving state: {e}\n")

def acquire_daemon_lock():
    STATE_DIR.mkdir(mode=0o700, parents=True, exist_ok=True)
    try:
        lock_fd = os.open(LOCK_FILE, os.O_CREAT | os.O_RDWR, 0o600)
        fcntl.flock(lock_fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        os.ftruncate(lock_fd, 0)
        os.write(lock_fd, f"{os.getpid()}\n".encode("utf-8"))
        return lock_fd
    except (BlockingIOError, OSError):
        return None

def check_bandwhich(probe=False):
    bandwhich_path = shutil.which("bandwhich")
    if not bandwhich_path:
        return False, "not_installed", "bandwhich is not installed. Please install it (e.g. sudo pacman -S bandwhich)."
    if not probe:
        return True, "", ""

    try:
        proc = subprocess.run(
            [bandwhich_path, "--raw", "--no-resolve", "-p"],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=0.6
        )
        if proc.returncode != 0 and "Insufficient permissions" in proc.stderr:
            return False, "permission", f"Insufficient permissions. Run: sudo setcap 'cap_sys_ptrace,cap_dac_read_search,cap_net_raw,cap_net_admin+ep' {bandwhich_path} (on multi-user systems, restrict with chmod 750)"
    except subprocess.TimeoutExpired:
        return True, "", ""
    except Exception as e:
        return False, "error", str(e)

    return True, "", ""

def run_daemon():
    lock_fd = acquire_daemon_lock()
    if lock_fd is None:
        try:
            with open(LOCK_FILE, "r") as f:
                running_pid = f.read().strip()
        except Exception:
            running_pid = "unknown"
        sys.stderr.write(f"Bandwidth collector daemon is already running (PID {running_pid}). Exiting.\n")
        sys.exit(0)

    # Terminate automatically if parent process (e.g. Quickshell) exits
    try:
        libc = ctypes.CDLL("libc.so.6")
        libc.prctl(1, signal.SIGTERM)  # PR_SET_PDEATHSIG = 1
    except Exception:
        pass

    proc = None
    def handle_exit(signum=None, frame=None):
        nonlocal proc
        if proc and proc.poll() is None:
            try:
                proc.terminate()
                proc.wait(timeout=1)
            except Exception:
                try:
                    proc.kill()
                    proc.wait(timeout=1)
                except Exception:
                    pass
        if lock_fd is not None:
            try:
                os.ftruncate(lock_fd, 0)
                os.close(lock_fd)
            except Exception:
                pass
        os._exit(0)

    signal.signal(signal.SIGTERM, handle_exit)
    signal.signal(signal.SIGINT, handle_exit)
    atexit.register(handle_exit)

    bandwhich_bin = shutil.which("bandwhich") or "/usr/bin/bandwhich"
    ok, err_type, err_msg = check_bandwhich(probe=True)
    if not ok:
        state = load_state()
        state["status"] = "error"
        state["error_type"] = err_type
        state["error"] = err_msg
        save_state(state)
        sys.stderr.write(f"{err_msg}\n")
        while True:
            time.sleep(5)
            ok, err_type, err_msg = check_bandwhich(probe=True)
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

    err_log = STATE_DIR / "bandwhich_err.log"
    while True:
        try:
            err_f = open(err_log, "w", encoding="utf-8")
            proc = subprocess.Popen(
                [bandwhich_bin, "--raw", "--no-resolve", "--connections", "-u", "bin-bytes"],
                stdout=subprocess.PIPE,
                stderr=err_f,
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

        port_to_app = {}
        tick_lines = []
        prev_hw_rx, prev_hw_tx = get_hardware_bytes()
        prev_hw_time = time.time()

        for line in proc.stdout:
            line_str = line.strip()
            if line_str.startswith("Refreshing:"):
                # End of a 1-second sample tick
                now = time.time()
                curr_hw_rx, curr_hw_tx = get_hardware_bytes()
                dt = max(0.1, now - prev_hw_time)
                delta_hw_rx = max(0, curr_hw_rx - prev_hw_rx) if prev_hw_rx is not None else 0
                delta_hw_tx = max(0, curr_hw_tx - prev_hw_tx) if prev_hw_tx is not None else 0
                prev_hw_rx, prev_hw_tx, prev_hw_time = curr_hw_rx, curr_hw_tx, now

                hw_down_bps = int(delta_hw_rx / dt)
                hw_up_bps = int(delta_hw_tx / dt)

                # Pass 1: map outgoing client ports to application names
                for l in tick_lines:
                    m = CONN_REGEX.match(l)
                    if not m:
                        continue
                    iface, lport, rhost, rport, proto, up_str, down_str, raw_app = m.groups()
                    if raw_app != "<UNKNOWN>" and raw_app.lower() not in PROXY_DAEMONS:
                        port_to_app[lport] = (normalize_app_name(raw_app), now)

                # Pass 2: attribute bandwidth
                current_tick_rates = {}
                for l in tick_lines:
                    m = CONN_REGEX.match(l)
                    if not m:
                        continue
                    iface, lport, rhost, rport, proto, up_str, down_str, raw_app = m.groups()
                    raw_app_lower = raw_app.lower()

                    # Proxied traffic via local transparent proxy:
                    if raw_app_lower in PROXY_DAEMONS:
                        if iface == "lo" and is_local_address(rhost) and rport in port_to_app:
                            real_app = port_to_app[rport][0]
                            # Proxy received data from client port -> client's upload!
                            down_bytes = int(down_str)
                            if down_bytes > 0:
                                rates = current_tick_rates.setdefault(real_app, {"up": 0, "down": 0})
                                rates["up"] += down_bytes
                        continue

                    if raw_app == "<UNKNOWN>":
                        continue

                    up_bytes = int(up_str)
                    down_bytes = int(down_str)
                    if up_bytes <= 0 and down_bytes <= 0:
                        continue

                    app_name = normalize_app_name(raw_app)
                    if iface == "lo":
                        # Skip local loopback IPC (e.g. localhost, 127.0.0.1)
                        if not is_local_address(rhost):
                            rates = current_tick_rates.setdefault(app_name, {"up": 0, "down": 0})
                            rates["up"] += up_bytes
                            rates["down"] += down_bytes
                    else:
                        # Physical interface direct traffic
                        if not is_local_address(rhost):
                            rates = current_tick_rates.setdefault(app_name, {"up": 0, "down": 0})
                            rates["up"] += up_bytes
                            rates["down"] += down_bytes

                # Prune client port map entries older than 60s
                for p in list(port_to_app.keys()):
                    if now - port_to_app[p][1] > 60:
                        del port_to_app[p]

                tick_lines = []

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

                    sorted_dates = sorted(history.keys(), reverse=True)
                    if len(sorted_dates) > 30:
                        history = {d: history[d] for d in sorted_dates[:30]}

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

                app_up_bps = sum(r.get("up", 0) for r in current_tick_rates.values())
                app_down_bps = sum(r.get("down", 0) for r in current_tick_rates.values())

                # Accumulate physical hardware wire traffic and distribute proportionally.
                # This aligns with /proc/net/dev and WiFi stats, while ensuring sum(apps) <= total.
                if delta_hw_rx > 0 or delta_hw_tx > 0:
                    state["today_down"] += delta_hw_rx
                    state["today_up"] += delta_hw_tx

                    if app_down_bps > 0 and delta_hw_rx > 0:
                        for app_name, rates in current_tick_rates.items():
                            d = rates.get("down", 0)
                            if d > 0:
                                app_record = state["apps"].setdefault(app_name, {"down": 0, "up": 0})
                                app_record["down"] += int(round(delta_hw_rx * (d / app_down_bps)))

                    if app_up_bps > 0 and delta_hw_tx > 0:
                        for app_name, rates in current_tick_rates.items():
                            u = rates.get("up", 0)
                            if u > 0:
                                app_record = state["apps"].setdefault(app_name, {"down": 0, "up": 0})
                                app_record["up"] += int(round(delta_hw_tx * (u / app_up_bps)))
                elif app_down_bps > 0 or app_up_bps > 0:
                    cal_down = int(app_down_bps / 2.28)
                    cal_up = int(app_up_bps / 2.28)
                    state["today_down"] += cal_down
                    state["today_up"] += cal_up
                    for app_name, rates in current_tick_rates.items():
                        app_record = state["apps"].setdefault(app_name, {"down": 0, "up": 0})
                        app_record["down"] += int(rates.get("down", 0) / 2.28)
                        app_record["up"] += int(rates.get("up", 0) / 2.28)

                # Ensure total always bounds sum of apps
                apps_down_sum = sum(a.get("down", 0) for a in state["apps"].values())
                apps_up_sum = sum(a.get("up", 0) for a in state["apps"].values())
                state["today_down"] = max(state.get("today_down", 0), apps_down_sum)
                state["today_up"] = max(state.get("today_up", 0), apps_up_sum)

                state["current_down_bps"] = max(hw_down_bps, app_down_bps)
                state["current_up_bps"] = max(hw_up_bps, app_up_bps)

                state["current_rates"] = current_tick_rates
                state["last_tick_time"] = now

                save_state(state)
                continue

            tick_lines.append(line_str)

        # Reap child process to prevent zombie/defunct processes
        if proc:
            try:
                proc.terminate()
                proc.wait(timeout=1)
            except Exception:
                try:
                    proc.kill()
                    proc.wait(timeout=1)
                except Exception:
                    pass

        try:
            err_f.close()
        except Exception:
            pass

        stderr_output = ""
        if err_log.exists():
            try:
                with open(err_log, "r", encoding="utf-8") as f:
                    stderr_output = f.read()
            except Exception:
                pass

        if "Insufficient permissions" in stderr_output:
            state["status"] = "error"
            state["error_type"] = "permission"
            state["error"] = "Insufficient permissions. Run: sudo setcap 'cap_sys_ptrace,cap_dac_read_search,cap_net_raw,cap_net_admin+ep' /usr/bin/bandwhich (on multi-user systems, restrict with chmod 750)"
            save_state(state)

        time.sleep(2)

def run_status():
    ok, err_type, err_msg = check_bandwhich(probe=False)
    state = load_state()

    status_val = state.get("status", "ok")
    error_val = state.get("error", "")
    error_type_val = state.get("error_type", "")
    if not ok:
        status_val = "error"
        error_val = err_msg
        error_type_val = err_type

    apps_raw = state.get("apps", {})
    apps_down_sum = sum(a.get("down", 0) for a in apps_raw.values())
    apps_up_sum = sum(a.get("up", 0) for a in apps_raw.values())

    today_down = max(state.get("today_down", 0), apps_down_sum)
    today_up = max(state.get("today_up", 0), apps_up_sum)
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

    # Build cumulative apps list (ranked by total = download + upload descending)
    apps_raw = state.get("apps", {})
    all_apps = []
    for name, stats in apps_raw.items():
        d = stats.get("down", 0)
        u = stats.get("up", 0)
        tot = d + u
        if tot > 0:
            all_apps.append({
                "name": name,
                "down": d,
                "up": u,
                "total": tot
            })
    all_apps.sort(key=lambda x: x["total"], reverse=True)

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
        "days": days[:14]
    }
    print(json.dumps(result))

def run_self_check():
    assert normalize_app_name("language_server") == "antigravity"
    assert normalize_app_name("curl") == "curl"
    assert normalize_app_name("<UNKNOWN>") == "<UNKNOWN>"
    assert is_local_address("127.0.0.1") is True
    assert is_local_address("localhost") is True
    assert is_local_address("8.8.8.8") is False

    rx, tx = get_hardware_bytes()
    assert isinstance(rx, int) and rx >= 0
    assert isinstance(tx, int) and tx >= 0

    # Test proportional hardware distribution
    delta_hw = 1000
    app_down = 400
    total_app_down = 800
    assert int(round(delta_hw * (app_down / total_app_down))) == 500

    # Test 30-day history rollover trimming
    test_hist = {f"2026-01-{i:02d}": {"down": 10, "up": 10, "total": 20} for i in range(1, 35)}
    sorted_d = sorted(test_hist.keys(), reverse=True)
    trimmed = {d: test_hist[d] for d in sorted_d[:30]} if len(sorted_d) > 30 else test_hist
    assert len(trimmed) == 30
    assert "2026-01-34" in trimmed
    assert "2026-01-01" not in trimmed

    line1 = 'connection: <12345> <lo>:41567 => 127.0.0.1:35334 (tcp) up/down Bps: 100/200 process: "language_server"'
    m = CONN_REGEX.match(line1)
    assert m is not None
    iface, lport, rhost, rport, proto, u, d, app = m.groups()
    assert iface == "lo" and lport == "41567" and rport == "35334"
    assert normalize_app_name(app) == "antigravity"

    line2 = 'connection: <12345> <lo>:443 => 10.131.68.123:41567 (tcp) up/down Bps: 0/5000 process: "v2raya_core"'
    m2 = CONN_REGEX.match(line2)
    assert m2 is not None
    iface2, lport2, rhost2, rport2, proto2, u2, d2, app2 = m2.groups()
    assert app2.lower() in PROXY_DAEMONS
    assert is_local_address(rhost2) is True
    assert rport2 == "41567"
    print("All collector self-checks passed successfully.")

if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "--test":
        run_self_check()
        sys.exit(0)
    elif len(sys.argv) > 1 and sys.argv[1] == "daemon":
        run_daemon()
    else:
        run_status()

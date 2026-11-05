#!/usr/bin/env python3
"""
CROUS Housing Real-Time Watcher (macOS, Cloud & Mobile Push via ntfy.sh)
Checks CROUS housing search every few seconds, sends phone push notifications (ntfy.sh)
and macOS desktop notifications on any change.
Also exposes a lightweight HTTP status server if PORT env var is set (for 24/7 free cloud hosting).
"""

import argparse
import json
import os
import re
import subprocess
import sys
import threading
import time
import urllib.request
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent
CONFIG_FILE = BASE_DIR / "config.json"
STATE_FILE = BASE_DIR / "crous_state.json"
LOG_FILE = BASE_DIR / "crous_watcher.log"

DEFAULT_SEARCH_URL = "https://trouverunlogement.lescrous.fr/tools/48/search?bounds=1.5573120117187502_49.384160800744986_3.0926513671875004_47.92002350993272"
DEFAULT_INTERVAL = 10
DEFAULT_PLAY_SOUND = True
DEFAULT_OPEN_BROWSER = True
DEFAULT_NTFY_TOPIC = "crous-zak-2729fc55"

IS_MAC = sys.platform == "darwin"

COLORS = {
    "Cyan": "\033[96m",
    "Green": "\033[92m",
    "Yellow": "\033[93m",
    "Red": "\033[91m",
    "Magenta": "\033[95m",
    "Gray": "\033[90m",
    "DarkGray": "\033[90m",
    "White": "\033[97m",
    "Reset": "\033[0m",
}

STATUS = {
    "last_check": None,
    "total_listings": 0,
    "iterations": 0,
    "listings": {},
}


def load_config():
    cfg = {
        "searchUrl": os.environ.get("CROUS_SEARCH_URL", DEFAULT_SEARCH_URL),
        "checkIntervalSeconds": int(os.environ.get("CROUS_INTERVAL", DEFAULT_INTERVAL)),
        "playSound": DEFAULT_PLAY_SOUND,
        "openBrowserOnNewListing": DEFAULT_OPEN_BROWSER,
        "ntfyTopic": os.environ.get("NTFY_TOPIC", DEFAULT_NTFY_TOPIC),
    }
    if CONFIG_FILE.exists():
        try:
            with open(CONFIG_FILE, "r", encoding="utf-8") as f:
                user_cfg = json.load(f)
            if user_cfg.get("searchUrl") and "CROUS_SEARCH_URL" not in os.environ:
                cfg["searchUrl"] = str(user_cfg["searchUrl"])
            if user_cfg.get("checkIntervalSeconds") is not None and "CROUS_INTERVAL" not in os.environ:
                cfg["checkIntervalSeconds"] = int(user_cfg["checkIntervalSeconds"])
            if user_cfg.get("playSound") is not None:
                cfg["playSound"] = bool(user_cfg["playSound"])
            if user_cfg.get("openBrowserOnNewListing") is not None:
                cfg["openBrowserOnNewListing"] = bool(user_cfg["openBrowserOnNewListing"])
            if user_cfg.get("ntfyTopic") and "NTFY_TOPIC" not in os.environ:
                cfg["ntfyTopic"] = str(user_cfg["ntfyTopic"]).strip()
        except Exception as e:
            print(f"{COLORS['Yellow']}Warning: Could not parse config.json ({e}), using defaults.{COLORS['Reset']}")
    return cfg


def log_message(message: str, color: str = "White"):
    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    line = f"[{timestamp}] {message}"
    ansi = COLORS.get(color, COLORS["White"])
    print(f"{ansi}{line}{COLORS['Reset']}", flush=True)
    try:
        with open(LOG_FILE, "a", encoding="utf-8") as f:
            f.write(line + "\n")
    except Exception:
        pass


def send_phone_push(topic: str, title: str, message: str, click_url: str = "", urgent: bool = True):
    """Send instant mobile push notification via ntfy.sh."""
    if not topic:
        return
    try:
        req = urllib.request.Request(
            f"https://ntfy.sh/{topic}",
            data=message.encode("utf-8"),
            method="POST",
        )
        # HTTP headers must be ASCII/Latin-1 safe; strip emojis from header or encode via RFC2047
        ascii_title = title.encode("ascii", "ignore").decode("ascii").strip() or "CROUS Alert"
        req.add_header("Title", ascii_title)
        req.add_header("Priority", "max" if urgent else "default")
        req.add_header("Tags", "house,rotating_light" if urgent else "information_source")
        if click_url:
            req.add_header("Click", click_url)
            req.add_header("Actions", f"view, Ouvrir le logement, {click_url}, clear=true")
        with urllib.request.urlopen(req, timeout=10) as _:
            pass
    except Exception as e:
        log_message(f"Phone push (ntfy) warning: {e}", "Yellow")


def send_notification(title: str, message: str, play_sound: bool = True, ntfy_topic: str = "", url: str = "", urgent: bool = True):
    # 1. Send phone notification via ntfy.sh
    if ntfy_topic:
        send_phone_push(ntfy_topic, title, message, click_url=url, urgent=urgent)

    # 2. Send macOS desktop notification if running locally on Mac
    if IS_MAC:
        try:
            clean_title = title.replace('"', '\\"').replace("\n", " ")
            clean_msg = message.replace('"', '\\"').replace("\n", " — ")
            script = f'display notification "{clean_msg}" with title "{clean_title}"'
            if play_sound:
                script += ' sound name "Glass"'
            subprocess.run(["/usr/bin/osascript", "-e", script], check=False, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            if play_sound and os.path.exists("/System/Library/Sounds/Glass.aiff"):
                subprocess.Popen(
                    ["/usr/bin/afplay", "/System/Library/Sounds/Glass.aiff"],
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                )
        except Exception as e:
            log_message(f"macOS notification warning: {e}", "Yellow")


def open_browser(url: str):
    if not url:
        return
    # Skip opening browser in headless/cloud environments
    if not IS_MAC and not os.environ.get("DISPLAY"):
        return
    try:
        if IS_MAC:
            subprocess.Popen(["/usr/bin/open", url], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        else:
            import webbrowser
            webbrowser.open(url)
    except Exception as e:
        log_message(f"Failed to open browser: {e}", "Yellow")


def fetch_html(url: str) -> str:
    result = subprocess.run(
        [
            "curl",
            "-s",
            "-L",
            "--retry",
            "2",
            "--retry-delay",
            "1",
            "--max-time",
            "15",
            "-H",
            "User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
            "-H",
            "Accept: text/html,application/xhtml+xml,application/xml",
            url,
        ],
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
    )
    return result.stdout or ""


def parse_listings(html: str):
    if not html or len(html) < 1000:
        raise ValueError(f"Empty or invalid response from CROUS server (length: {len(html)})")

    match = re.search(r'data-url="[^"]*search[^"]*"[^>]*>\s*(\{.*?\})\s*</script>', html, re.DOTALL)
    if not match:
        raise ValueError("Could not find search results script block in HTML")

    raw_json = match.group(1)
    data = json.loads(raw_json)
    search_results = json.loads(data["body"])

    total = search_results.get("results", {}).get("total", {}).get("value", 0)
    items = search_results.get("results", {}).get("items", []) or []

    current_listings = {}
    for item in items:
        item_id = str(item.get("id", ""))
        if not item_id:
            continue
        residence = item.get("residence") or {}
        label = residence.get("label", f"Listing #{item_id}")
        address = residence.get("address", "")

        occ_modes = item.get("occupationModes") or []
        rents = [
            m.get("rent", {}).get("min")
            for m in occ_modes
            if isinstance(m.get("rent"), dict) and m.get("rent", {}).get("min") is not None
        ]
        rent_min = min(rents) if rents else None
        rent_eur = round(rent_min / 100.0, 2) if rent_min else 0

        area_obj = item.get("area") or {}
        area = f"{area_obj.get('min', '?')}-{area_obj.get('max', '?')} m²"
        url = f"https://trouverunlogement.lescrous.fr/tools/48/accommodations/{item_id}"

        current_listings[item_id] = {
            "id": item_id,
            "label": label,
            "rent": rent_eur,
            "area": area,
            "address": address,
            "url": url,
        }

    return total, current_listings


def save_state(total: int, listings: dict):
    state_obj = {
        "lastUpdate": datetime.now(timezone.utc).isoformat(),
        "total": total,
        "ids": sorted(listings.keys()),
        "listings": listings,
    }
    with open(STATE_FILE, "w", encoding="utf-8") as f:
        json.dump(state_obj, f, indent=2, ensure_ascii=False)


class StatusHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.end_headers()
        self.wfile.write(json.dumps(STATUS, ensure_ascii=False, indent=2).encode("utf-8"))

    def log_message(self, format, *args):
        pass


def start_health_server(port: int):
    server = HTTPServer(("0.0.0.0", port), StatusHandler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    log_message(f"Cloud HTTP health-check server listening on port {port}", "Green")


def main():
    parser = argparse.ArgumentParser(description="CROUS Housing Watcher")
    parser.add_argument("--test-notify", action="store_true", help="Send a test notification to phone & desktop and exit")
    parser.add_argument("--max-minutes", type=float, default=0, help="Stop automatically after N minutes (useful for GitHub Actions)")
    args = parser.parse_args()

    cfg = load_config()
    search_url = cfg["searchUrl"]
    interval_seconds = cfg["checkIntervalSeconds"]
    play_sound = cfg["playSound"]
    open_browser_on_new = cfg["openBrowserOnNewListing"]
    ntfy_topic = cfg["ntfyTopic"]

    if args.test_notify:
        log_message(f"Sending test notification to ntfy topic '{ntfy_topic}'...", "Cyan")
        send_notification(
            "NEW CROUS HOUSING AVAILABLE! (TEST)",
            "Residence Test CROUS | 350 EUR/mo | 18-20 m²\nCliquez pour ouvrir la page CROUS",
            play_sound=play_sound,
            ntfy_topic=ntfy_topic,
            url="https://trouverunlogement.lescrous.fr",
            urgent=True,
        )
        log_message(f"Test sent! Check your phone in the ntfy app subscribed to: {ntfy_topic}", "Green")
        return

    port = os.environ.get("PORT")
    if port:
        start_health_server(int(port))

    print(f"{COLORS['Cyan']}=========================================================={COLORS['Reset']}")
    print(f"{COLORS['Cyan']}      CROUS HOUSING REAL-TIME WATCHER                     {COLORS['Reset']}")
    print(f"{COLORS['Cyan']}=========================================================={COLORS['Reset']}")
    log_message(f"Monitoring CROUS listings every {interval_seconds} seconds...", "Cyan")
    log_message(f"Phone Push Topic (ntfy.sh): {ntfy_topic or 'Disabled'}", "Green")
    log_message(f"Auto-open browser on new listing: {open_browser_on_new}", "Gray")
    log_message(f"Search URL: {search_url}", "Gray")
    log_message("==========================================================", "Cyan")

    known_listings = {}
    is_first_run = not STATE_FILE.exists()

    if not is_first_run:
        try:
            with open(STATE_FILE, "r", encoding="utf-8") as f:
                saved = json.load(f)
            if isinstance(saved.get("listings"), dict):
                for k, v in saved["listings"].items():
                    known_listings[str(k)] = v
            elif isinstance(saved.get("ids"), list):
                for item_id in saved["ids"]:
                    known_listings[str(item_id)] = {"id": str(item_id)}
            log_message(f"Loaded {len(known_listings)} existing listing(s) from state cache.", "Yellow")
        except Exception:
            log_message("Creating new state cache.", "Yellow")
            is_first_run = True

    iteration = 0
    consecutive_errors = 0
    start_time = time.time()

    try:
        while True:
            if args.max_minutes > 0 and (time.time() - start_time) >= (args.max_minutes * 60):
                log_message(f"Reached max run time ({args.max_minutes} min). Exiting cleanly.", "Cyan")
                break

            iteration += 1
            try:
                html = fetch_html(search_url)
                total, current_listings = parse_listings(html)

                STATUS["last_check"] = datetime.now(timezone.utc).isoformat()
                STATUS["total_listings"] = total
                STATUS["iterations"] = iteration
                STATUS["listings"] = current_listings

                if is_first_run:
                    known_listings = current_listings
                    is_first_run = False
                    log_message(f"Initial baseline established: {total} listing(s) found.", "Green")
                    for item in current_listings.values():
                        log_message(f"  - {item['label']} ({item['rent']} EUR) -> {item['address']}", "Gray")
                    save_state(total, current_listings)
                else:
                    new_ids = [k for k in current_listings if k not in known_listings]
                    removed_ids = [k for k in known_listings if k not in current_listings]

                    if new_ids or removed_ids:
                        log_message("**********************************************************", "Magenta")
                        log_message(f">>> DIFFERENCE DETECTED! Total listings: {total} <<<", "Magenta")
                        log_message("**********************************************************", "Magenta")

                        for item_id in new_ids:
                            item = current_listings[item_id]
                            msg = f"{item['label']} | {item['rent']} EUR/mo | {item['area']}\n{item['address']}"
                            log_message(f"[NEW HOUSING AVAILABLE] {msg}", "Green")
                            send_notification(
                                "NEW CROUS HOUSING AVAILABLE!",
                                msg,
                                play_sound=play_sound,
                                ntfy_topic=ntfy_topic,
                                url=item["url"],
                                urgent=True,
                            )
                            if open_browser_on_new:
                                open_browser(item["url"])

                        for item_id in removed_ids:
                            old_item = known_listings.get(item_id, {})
                            old_label = old_item.get("label") or f"Listing #{item_id}"
                            log_message(f"[LISTING REMOVED / TAKEN] {old_label}", "Red")
                            send_notification(
                                "CROUS Listing Removed",
                                f"{old_label} is no longer available.",
                                play_sound=play_sound,
                                ntfy_topic=ntfy_topic,
                                urgent=False,
                            )

                        known_listings = current_listings
                        save_state(total, current_listings)
                    else:
                        if iteration % 6 == 1:
                            log_message(f"Check #({iteration}): {total} listing(s) active. No changes.", "DarkGray")

                consecutive_errors = 0
            except Exception as e:
                consecutive_errors += 1
                log_message(f"Check #({iteration}) Network warning: {e}", "Yellow")
                if consecutive_errors == 10:
                    send_notification(
                        "CROUS Monitor Alert",
                        "10 consecutive connection failures to CROUS site.",
                        play_sound=play_sound,
                        ntfy_topic=ntfy_topic,
                        urgent=False,
                    )

            time.sleep(interval_seconds)
    except KeyboardInterrupt:
        print()
        log_message("Watcher stopped by user.", "Yellow")


if __name__ == "__main__":
    main()

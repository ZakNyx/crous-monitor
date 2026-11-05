#!/bin/zsh
cd "$(dirname "$0")"
python3 ./crous_watcher.py --test-notify
echo ""
echo "Notification de test envoyée sur le canal ntfy : $(python3 -c 'import json; print(json.load(open("config.json")).get("ntfyTopic"))')"
sleep 3


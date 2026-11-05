#!/bin/zsh
cd "$(dirname "$0")"

# Stop any existing background instance first
pkill -f "crous_watcher\.(py|ps1)" 2>/dev/null

if command -v python3 >/dev/null 2>&1; then
    nohup python3 ./crous_watcher.py >/dev/null 2>&1 &
elif command -v pwsh >/dev/null 2>&1; then
    nohup pwsh -NoProfile -File ./crous_watcher.ps1 >/dev/null 2>&1 &
else
    osascript -e 'display alert "CROUS Monitor" message "Erreur : python3 ou pwsh introuvable." as critical'
    exit 1
fi

osascript -e 'display notification "Vous recevrez une notification macOS dès qu'\''un logement apparaît ou disparaît." with title "🏠 CROUS Monitor actif en arrière-plan" sound name "Glass"'
echo "Surveillance CROUS lancée en arrière-plan (PID: $!)."
echo "Pour arrêter, lancez ARRETER_SURVEILLANCE.command"
sleep 2

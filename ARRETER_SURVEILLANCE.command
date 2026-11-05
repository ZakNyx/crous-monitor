#!/bin/zsh
echo "Arrêt du moniteur CROUS..."
pkill -f "crous_watcher\.(py|ps1)" 2>/dev/null
osascript -e 'display notification "La surveillance CROUS a été arrêtée." with title "🛑 CROUS Monitor arrêté"' 2>/dev/null
echo "Moniteur arrêté."
sleep 2

#!/bin/zsh
cd "$(dirname "$0")"
clear
echo ""
echo "=============================================================="
echo "       CROUS Real-Time Housing Monitor (macOS)"
echo "=============================================================="
echo ""
echo "Lancement du script de surveillance..."
echo "Verifications toutes les 10 secondes."
echo "Pour quitter, appuyez sur Ctrl+C ou fermez cette fenetre."
echo ""

if command -v python3 >/dev/null 2>&1; then
    python3 ./crous_watcher.py
elif command -v pwsh >/dev/null 2>&1; then
    pwsh -NoProfile -File ./crous_watcher.ps1
else
    echo "Erreur : python3 ou pwsh est requis."
    read -k 1 "?Appuyez sur une touche pour fermer..."
fi

# 🏠 CROUS Real-Time Housing Monitor / Surveillance Logements CROUS

Script automatique qui surveille les logements CROUS toutes les 10 secondes et vous alerte dès qu'un logement apparaît, disparaît ou change !

---

## ⚡ Démarrage Rapide / Quick Start

### Option 1 : Avec fenêtre visible (Recommandé au début)
Double-cliquez sur **`DEMARRER_SURVEILLANCE.bat`** (ou `START_MONITOR.bat`).
- Une fenêtre s'ouvre et affiche l'état de chaque vérification en temps réel.
- Pour arrêter : fermez simplement la fenêtre.

### Option 2 : En arrière-plan (Sans fenêtre ouverte)
Double-cliquez sur **`DEMARRER_EN_ARRIERE_PLAN.vbs`**.
- Le script tourne silencieusement en tâche de fond.
- Vous recevrez une notification Windows dès qu'un logement change.
- Pour l'arrêter : double-cliquez sur **`ARRETER_SURVEILLANCE.bat`**.

### macOS
Deux options sont disponibles sur macOS :

#### Via le Finder (Double-clic)
- **`DEMARRER_SURVEILLANCE.command`** : Ouvre une fenêtre Terminal et affiche la surveillance en direct.
- **`DEMARRER_EN_ARRIERE_PLAN.command`** : Lance la surveillance silencieusement en arrière-plan avec notifications macOS natives (`osascript` + son d'alerte `afplay`).
- **`ARRETER_SURVEILLANCE.command`** : Arrête la surveillance en arrière-plan.

#### Via le Terminal
Vous pouvez lancer soit le script Python natif (sans aucune installation requise), soit le script PowerShell :
```bash
cd ~/Downloads/crous_monitor

# Option A : Python 3 natif macOS (Recommandé)
python3 ./crous_watcher.py

# Option B : PowerShell (si pwsh est installé)
pwsh -NoProfile -File ./crous_watcher.ps1
```
Arrêtez avec `Ctrl+C`.

Sur macOS, le script envoie des **notifications macOS natives** accompagnées d'un son système (`Glass.aiff`) et ouvre automatiquement votre navigateur par défaut (`open`) dès qu'un nouveau logement est détecté.

---

## 🔔 Fonctionnalités
1. **Vérification toutes les 10 secondes** ultra-rapide et légère (utilise `curl`).
2. **Notification Windows (Toast)** avec son de carillon dès qu'un logement apparaît ou disparaît.
3. **Ouverture automatique du navigateur** : dès qu'un nouveau logement est détecté, votre navigateur ouvre directement la page du logement pour que vous puissiez réserver avant tout le monde !
4. **Historique des logs** : stocké dans `crous_watcher.log`.

---

## ⚙️ Configuration (`config.json`)
Ouvrez le fichier `config.json` avec le Bloc-notes pour personnaliser :
- `searchUrl` : Le lien de votre recherche CROUS (avec vos filtres de ville, dates, etc.).
- `checkIntervalSeconds` : Fréquence de vérification en secondes (défaut : 10).
- `playSound` : `true` pour activer le son d'alerte, `false` pour couper.
- `openBrowserOnNewListing` : `true` pour ouvrir automatiquement la page dès qu'un nouveau logement apparaît.

---

## 💻 Prérequis
- Windows 10 ou Windows 11.
- Aucun logiciel à installer (utilise PowerShell et curl intégrés à Windows).

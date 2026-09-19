# Fiche d’automatisation : ce qui peut encore être automatisé

## Objectif

Identifier les tâches encore manuelles et les transformer en flux totalement automatiques pour que l’utilisateur final n’ait plus à comprendre ni le système, ni les détails techniques du modèle, ni la configuration Linux.

---

## 1. Ce qui est déjà automatisé

### 1.1 Gestion du launcher
- affichage des options de menu
- routage des commandes vers les scripts
- validation de syntaxe des scripts Bash
- test de configuration et de non-régression
- détection des chemins et correctifs de regression
- test automatique des dépendances système (`tests/dependencies/`) : toolchain de build, Python/pip, réseau, GPU/systemd, outillage des tests

### 1.2 Gestion du réseau
- check internet
- watchdog de connexion
- reconnexion NetworkManager

### 1.3 Gestion du backend
- détection de `llama-server`
- installation depuis source si absent (dans `/usr/local/bin` avec sudo, ou `~/.local/bin` sans sudo)
- préparation du service systemd
- installation / activation du service via `systemctl`
- **fonctionnement sans sudo/root/systemd** : repli automatique en mode local (process suivi par fichier PID) pour `install`/`start`/`stop`/`restart`/`status`, y compris depuis `giga-serve.sh`
- bascule automatique de `MODEL_DIR`/`LOGDIR` vers `$HOME/.local` quand les chemins configurés (`/opt/...`) ne sont pas inscriptibles
- validation locale de l’API OpenAI-compatible
- génération de `.env` cohérent avant le démarrage

### 1.4 Gestion du modèle
- possibilité de cibler un dépôt HF GGUF
- téléchargement de GGUF dans un dossier de modèles
- validation de présence des fichiers `.gguf`
- réécriture automatique de `MODEL_FILENAME` selon le modèle réel présent

---

## 2. Ce qui reste encore manuel et doit être automatisé

### 2.1 Droits sudo / permissions système — **résolu différemment**
Problème d'origine :
- l’utilisateur courant n’a pas les droits sudo
- le lancement du service systemd nécessite les privilèges root

Ce qui a été fait (au lieu d'accorder sudo automatiquement à l'utilisateur, ce qui serait une élévation de privilèges non désirable) :
- `scripts/ensure-llama-server.sh`, `scripts/llama-ornith-serve.sh` et `scripts/giga-serve.sh` détectent l'absence de root/sudo et basculent automatiquement en **mode local** : binaire installé dans `~/.local/bin`, serveur lancé en process suivi par fichier PID (au lieu d'une unité systemd), `MODEL_DIR`/`LOGDIR` repliés sur `$HOME/.local` si les chemins configurés ne sont pas inscriptibles.
- `install`/`start`/`stop`/`restart`/`status` fonctionnent donc sans sudo, sans intervention utilisateur.
- couvert par `tests/connectionStatus/test_no_sudo_local_mode.sh` (comportemental) et `tests/connectionStatus/test_launcher_no_sudo_requirement.sh` (non-régression).

Limite restant volontairement manuelle :
- le mode local ne survit pas à un redémarrage ni à un crash (pas de `Restart=always`) ; seule l'installation systemd (`sudo ./scripts/llama-ornith-serve.sh install` ou `./launch.sh systemd`) apporte la persistance. Si une persistance sans sudo est requise, envisager un service utilisateur `systemctl --user` (nécessite que `loginctl enable-linger` soit accordé une fois par un admin).

### 2.2 Création du compte `llmuser`
Problème :
- le compte serveur dédié n’existe pas toujours
- il faut vérifier son existence, son home, son groupe, son shell, ses droits d’écriture

À automatiser :
- creation du compte si absent
- creation du dossier home
- configuration du shell système
- creation du groupe d’appartenance
- attribution des permissions sur les dossiers modèles/logs

### 2.3 Dossier de modèles et logs
Problème :
- le dossier `/opt/models` ou `$HOME/.local/models` peut être absent
- le dossier de logs systemd peut être absent
- les droits sur fichiers peuvent être incorrects

À automatiser :
- vérifier si `MODEL_DIR` existe
- le créer avec bons droits
- créer `/opt/hermes-llm/logs` ou équivalent
- donner les permissions au compte `llmuser`
- gérer les permissions de lecture/écriture de `llama-server`

### 2.4 Service systemd — **partiellement résolu**
Problème :
- le service n’est pas installé tant que la commande sudo et le binaire sont présents
- la configuration `ExecStart` doit correspondre exactement au bon modèle
- la portée du service doit être validée

Fait :
- écriture automatique de l'unité systemd, `daemon-reload`, `enable --now` (`scripts/llama-ornith-serve.sh install`, `scripts/bootstrap-systemd.sh`)
- validation du statut via `systemctl is-active` / `status`
- repli automatique en mode local (fichier PID) quand systemd/root n'est pas disponible, plutôt que d'échouer (voir 2.1)

Reste à faire :
- redémarrage automatique du process local si `llama-server` crashe ou si le binaire disparaît (le mode systemd a déjà `Restart=always`, le mode local non)

### 2.5 Couverture du modèle GGUF
Problème :
- le dépôt choisi peut contenir des `.safetensors` au lieu de `.gguf`
- le script doit percevoir le mauvais type de dépôt et passer à la conversion ou au bon repo

À automatiser :
- détecter automatiquement si les fichiers de repo sont `.gguf` ou `.safetensors`
- si `.safetensors`, lancer une logique conversion
- si repo GGUF, télécharger les bons fichiers
- choisir le bon fichier par défaut selon le budget GPU et la mémoire

### 2.6 Fichier de config `.env`
Problème :
- la config doit être cohérente entre `MODEL_DIR`, `MODEL_FILENAME`, `LISTEN_PORT`, `CTX_SIZE`, etc.
- l’utilisateur peut passer par des valeurs incohérentes

À automatiser :
- générer un `.env` cohérent
- vérifier que le fichier model existe réellement avant d’écrire la config
- réécrire `MODEL_FILENAME` automatiquement si le modèle a été téléchargé ou converti
- valider `CTX_SIZE` en fonction de la VRAM disponible

Implémentation actuelle :
- script dédié : `scripts/bootstrap-config.sh`
- commande launcher : `./launch.sh bootstrap`
- vérification des valeurs par défaut et du `.gguf` réel dans le test `tests/connectionStatus/test_env_bootstrap.sh`

### 2.7 Détection GPU / RUNTIME
Problème :
- le script sait que la GPU est NVIDIA RTX 3060, mais ne mesure pas automatiquement la VRAM ni la compatibilité
- le nombre de couches GPU à offloader reste souvent manuel

À automatiser :
- détecter `nvidia-smi`
- lire VRAM, mémoire totale, utili.
- calculer automatiquement un `--gpu-layers` raisonnable
- tester le service et ajuster si le modèle ne démarre pas

### 2.8 Validation API locale
Problème :
- le service peut être installé mais pas encore réellement serviceable
- les endpoints OpenAI ne sont pas testés automatiquement

À automatiser :
- lancer `curl http://127.0.0.1:8080/v1/models`
- vérifier le code HTTP 200
- tester une requête minimum `chat/completions`
- retourner un status clair à l’utilisateur

Implémentation actuelle :
- script dédié : `scripts/api-validate.sh`
- commande launcher : `./launch.sh api`
- test de non-régression : `tests/connectionStatus/test_api_validation.sh`

### 2.9 Démarrage de la machine cible
Problème :
- l’utilisateur doit encore savoir si le service démarre au reboot

À automatiser :
- activer le service avec `systemctl enable --now`
- valider sa persistance après redémarrage
- enregistrer un message de vérification final

---

## 3. Ce qui est maintenant à automatiser en priorité

### Priorité 1 — Sudo / permissions
C’est le plus important pour que le programme puisse réellement prendre la main.

Statut actuel : résolu par contournement (mode local sans sudo, voir 2.1) plutôt que par élévation de privilèges. Le service tourne sans sudo ; seule la persistance après reboot requiert encore un accès root ponctuel.

### Priorité 2 — création du compte `llmuser`
Sans compte serveur dédié, le service n’est pas propre ni fiable.

### Priorité 3 — génération automatique du `.env`
Le code doit être capable d’écrire un `.env` cohérent sans interventions humaines.

### Priorité 4 — création du service systemd
Sans ceci, il n’y a pas de backend stable.

Statut actuel : implémenté via `scripts/bootstrap-systemd.sh` et `scripts/llama-ornith-serve.sh install`, validé par `tests/connectionStatus/test_systemd_bootstrap.sh`. Complété par un mode local automatique quand systemd n'est pas utilisable (voir 2.1/2.4).

### Priorité 5 — conversion ou téléchargement du GGUF
Le système doit choisir automatiquement le bon chemin sans demander au user quel modèle utiliser.

### Priorité 6 — test API complet
Une fois le service lancé, l’application doit vérifier qu’il répond vraiment.

Statut actuel : implémenté via `scripts/api-validate.sh` et la commande `./launch.sh api`.

---

## 4. Ce que l’utilisateur ne doit plus voir

Le but est de contraindre le système à masquer tous ces détails techniques :
- comptes Linux
- droits sudo
- service systemd
- modèle GGUF exact
- repo Hugging Face source
- conversion vers GGUF
- `MODEL_FILENAME`
- `LISTEN_PORT`
- `CTX_SIZE`
- diagnostics de backend

Le programme doit exposer une interface simple, par exemple :

```bash
./launch.sh install
```

et sous le capot il fait :
- utiliser sudo si disponible (installation persistante), sinon basculer automatiquement en mode local sans sudo
- créer le compte si besoin
- installer llama-server si absent
- télécharger ou convertir le bon GGUF
- configurer `.env`
- installer le service systemd si possible, sinon démarrer en mode local
- démarrer le serveur
- valider l’API

---

## 5. Synthèse

Le projet est déjà bien avancé pour la partie “menu” et “vérification”.
Le point restant majeur n’est plus la logique d’UI, mais la logique d’auto-bootstrap système.

La prochaine étape de transformation la plus rentable est :
- rendre le programme capable de corriger automatiquement les prérequis système sans que l’utilisateur ait à intervenir.

---

## 6. Prochaine étape recommandée

Implémenter un script unique de bootstrap, par exemple :

```bash
./launch.sh bootstrap
```

qui exécute automatiquement :
1. check sudo (optionnel : bascule en mode local si absent, voir 2.1)
2. create/verify `llmuser`
3. install `llama-server`
4. check/prepare model dir
5. ensure GGUF is present
6. write `.env`
7. install systemd unit if possible, else local mode
8. start service
9. test API
10. report status

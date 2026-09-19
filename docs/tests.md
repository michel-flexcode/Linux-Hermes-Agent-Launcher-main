# Strategie de tests

## Objectif

Les tests verifient que le projet respecte son architecture cible :

- Ubuntu reste utilisable normalement pour le compte administrateur;
- seul `llmuser` porte le service LLM;
- le service utilise `llama-server` fourni par llama.cpp;
- aucun script ne transforme le boot global en mode serveur;
- aucune quantification degradee Q3 ou chemin Ollama n'est deploye;
- Hermes utilise l'API OpenAI-compatible de llama.cpp;
- l'absence de sudo/root/systemd ne bloque jamais le demarrage du service (repli automatique en mode local par fichier PID).

Les tests locaux ne demarrent pas le vrai modele, n'utilisent pas de vrai GPU et ne modifient pas la configuration Ubuntu. Certains tests executent reellement les scripts (avec un faux binaire `llama-server`) dans un bac a sable temporaire, mais aucun ne demande `sudo` ni n'ecrit en dehors de `/tmp`.

## Structure

```text
tests/
├── architecture/
│   ├── test_user_isolation.sh
│   └── test_no_global_boot_change.sh
├── config/
│   ├── test_environment.sh
│   └── test_no_degraded_quantization.sh
├── dependencies/
│   ├── test_build_toolchain.sh
│   ├── test_python_runtime.sh
│   ├── test_network_tools.sh
│   ├── test_gpu_and_service_tools.sh
│   └── test_test_suite_tools.sh
├── connectionStatus/
│   ├── test_script_syntax.sh
│   ├── test_client_config.sh
│   ├── test_internet_watchdog.sh
│   ├── test_main_launcher.sh
│   ├── test_launcher_internet_regression.sh
│   ├── test_launcher_menu_options.sh
│   ├── test_launcher_no_sudo_requirement.sh
│   ├── test_llama_server_prereqs.sh
│   ├── test_llama_server_autodetect_install.sh
│   ├── test_no_sudo_local_mode.sh
│   ├── test_quickstart_command.sh
│   ├── test_model_download_flow.sh
│   ├── test_api_validation.sh
│   ├── test_env_bootstrap.sh
│   └── test_systemd_bootstrap.sh
└── run_all_tests.py
```

## Tests d'architecture

### `test_user_isolation.sh`

Verifie que :

- la valeur par defaut de `LLM_USER` est `llmuser`;
- l'unite systemd est generee avec `User=llmuser`;
- le groupe du service est `llmuser`;
- l'ancien compte `ollama` n'est plus utilise.

### `test_no_global_boot_change.sh`

Verifie qu'aucun script ne contient de commande active pour :

- basculer vers `multi-user.target`;
- appliquer directement `sysctl -w`;
- regenerer GRUB;
- modifier `GRUB_CMDLINE_LINUX`.

Ce test protege les autres comptes de la maison : le compte administrateur et les autres utilisateurs ne doivent pas etre transformes en comptes serveur.

## Tests de configuration

### `test_environment.sh`

Verifie les variables minimales de `config/.env.example` :

- `LLM_USER`;
- `MODEL_DIR`;
- `LOGDIR`;
- adresse et port d'ecoute;
- contexte `73728`;
- modele GGUF `Q4_K_M`.

### `test_no_degraded_quantization.sh`

Verifie que les scripts de deploiement :

- utilisent la configuration Q4_K_M;
- ne contiennent pas de chemin Q3;
- ne contiennent pas de fallback Ollama.

La politique du projet est de regler llama.cpp ou d'arreter proprement le service en cas de saturation memoire, plutot que de degrader le modele.

## Tests de connexion et scripts

### `test_script_syntax.sh`

Execute `bash -n` sur chaque script Bash du dossier `scripts/`.

### `test_client_config.sh`

Verifie que la configuration Hermes :

- utilise `providers.openai_compatible`;
- pointe vers `/v1`;
- ne propose pas Q3 ou Ollama.

### `test_internet_watchdog.sh`

Verifie que le watchdog :

- possede une URL et un intervalle configurables;
- utilise une verification reseau avec timeout;
- peut demander une reconnexion a NetworkManager;
- genere une unite systemd qui redemarre automatiquement.

### `test_main_launcher.sh`

Verifie le comportement du point d'entree `launch.sh` :

- la commande `help` expose toutes les commandes documentees;
- une commande inconnue retourne une erreur;
- le launcher principal est utilisable sans parcourir manuellement le dossier `scripts/`.

### `test_launcher_menu_options.sh`

Couvre la couche de routage du menu principal, de 1 a 7 :

- chaque option du menu appelle la bonne action;
- les alias du launcher (`setup`, `install`, `start`, `status`, `internet`, `watchdog`, etc.) pointent bien vers les bons scripts;
- le dispatcher est coherent avec la documentation de `launch.sh`.

### `test_launcher_internet_regression.sh`

Protège contre la régression observée sur l'option Internet :

- le launcher ne doit pas descendre dans `scripts/scripts`;
- l'option Internet ne doit pas échouer sur un fichier de log non accessible;
- la commande directe et le menu interactif doivent retourner un statut cohérent.

### `test_llama_server_prereqs.sh`

Verifie que le projet décrit bien les prérequis de fonctionnement de `llama.cpp` :

- présence des variables de configuration minimales;
- `LLM_USER=llmuser`;
- `LISTEN_HOST=0.0.0.0` et `LISTEN_PORT=8080`;
- `CTX_SIZE=73728`;
- `MODEL_FILENAME` compatible Q4_K_M;
- script de service exigeant un binaire `llama-server` et un chemin model valide.

### `test_llama_server_autodetect_install.sh`

Verifie que le projet fournit un flux de detection-installation automatique pour `llama-server` :

- le helper existe;
- il recherche le binaire sur les chemins standards;
- il propose un install depuis source via `git`, `make` et `cmake`/build;
- le script de service s'appuie bien sur ce mécanisme avant de lancer le serveur.

### `test_model_download_flow.sh`

Verifie que le projet propose bien un helper explicite de téléchargement du GGUF Orni th depuis Hugging Face :

- le script de téléchargement existe;
- il pointe vers le repo `ornith-ai/Ornith-1.5-35B-A3B`;
- il utilise `huggingface_hub` pour récupérer le `.gguf` dans le dossier de modèles;
- le launcher expose la commande `model` dans l’aide et le dispatcher.

### `test_launcher_no_sudo_requirement.sh`

Test statique (grep) qui protège le mode sans sudo introduit dans `launcher.sh`, `llama-ornith-serve.sh`, `giga-serve.sh` et `ensure-llama-server.sh` :

- le menu interactif ne doit plus imposer `Utilise sudo.` avant de gérer le service;
- `llama-ornith-serve.sh` doit exposer `start_local`/`stop_local`/`status_local`, `has_sudo` et une variable `IS_ROOT`;
- `ensure-llama-server.sh` doit exposer une installation locale (`install_from_source_local`) sans sudo;
- `giga-serve.sh` doit détecter si systemd est réellement utilisable (`uses_systemd`) et déléguer sinon à `llama-ornith-serve.sh`.

Ce test empêche une régression qui réintroduirait un `[[ "$(id -u)" -eq 0 ]] || fail ...` bloquant sur les commandes start/stop/status/restart.

### `test_no_sudo_local_mode.sh`

Test comportemental (pas seulement statique) qui exécute réellement les scripts dans un bac à sable isolé, sans toucher au `config/.env` du dépôt ni au système :

- copie `ensure-llama-server.sh`, `llama-ornith-serve.sh` et `giga-serve.sh` dans un projet temporaire avec son propre `config/.env` (chemins volontairement non inscriptibles, ex. `/root/...`) pour forcer le repli automatique;
- fournit un faux binaire `llama-server` (un simple `sleep` qui répond à `SIGTERM`) pour éviter tout téléchargement, compilation ou chargement de modèle réel;
- vérifie que `ensure-llama-server.sh` détecte un binaire déjà installé dans `~/.local/bin` sans relancer un `git clone`;
- vérifie que `llama-ornith-serve.sh start` bascule automatiquement `MODEL_DIR`/`LOGDIR` vers `$HOME/.local` et démarre un process suivi par fichier PID (sans systemd, sans root);
- vérifie que `status` détecte le process en cours et que `stop` le termine et supprime le fichier PID;
- vérifie que `giga-serve.sh status/stop` délèguent bien à ce même mécanisme local au lieu d'appeler `systemctl`.

Ce test ne nécessite ni sudo, ni root, ni GPU, ni modèle GGUF réel : il se termine en quelques secondes et nettoie systématiquement son bac à sable (`trap cleanup EXIT`).

### `test_quickstart_command.sh`

Vérifie que `./launch.sh quickstart` existe et enchaîne bien, dans l'ordre, `scripts/check-system-deps.sh` puis les étapes `setup`, `bootstrap`, `model`, `install`, `api` :

- `scripts/check-system-deps.sh` existe et est exécutable;
- il détecte root/sudo avant de lancer `apt-get install`;
- `launch.sh` documente `quickstart` dans son aide et route bien vers ces étapes dans l'ordre.

## Tests de dépendances (`tests/dependencies/`)

Ces tests vérifient que la machine hôte peut réellement exécuter le projet, en plus des vérifications statiques ci-dessus. Ils n'installent rien et ne demandent pas sudo.

### `test_build_toolchain.sh`

Si `llama-server` n'est pas déjà installé, vérifie que `git`, un système de build (`make` ou `cmake`) et un compilateur C/C++ (`gcc`/`g++`/`cc`) sont disponibles, sans quoi `scripts/ensure-llama-server.sh` ne peut pas compiler llama.cpp depuis les sources. Si `llama-server` est déjà présent, le test passe directement (rien à construire).

### `test_python_runtime.sh`

Vérifie `python3`, son module standard `json` (utilisé pour parser l'API OpenAI-compatible) et `pip` (nécessaire pour l'auto-installation de `huggingface_hub` par `scripts/download-ornith-model.sh`).

### `test_network_tools.sh`

Vérifie que `curl` est présent (exigence dure pour `scripts/api-validate.sh` et `scripts/internet-watchdog.sh`). Signale la présence de `nmcli` à titre informatif seulement : son absence dégrade déjà proprement la reconnexion automatique dans le code, donc ne fait pas échouer le test.

### `test_gpu_and_service_tools.sh`

Test informatif (n'échoue jamais sur l'absence des outils eux-mêmes) qui rapporte la disponibilité de `nvidia-smi` (GPU/VRAM) et `systemctl` (installation systemd persistante). Les deux sont optionnels depuis l'ajout du mode local sans sudo : leur absence est journalisée en `WARN` mais ne bloque rien.

### `test_test_suite_tools.sh`

Vérifie que `ripgrep` (`rg`) et `bash`, utilisés par la quasi-totalité des autres tests statiques, sont bien installés. Sans ce test, l'absence de `rg` provoquerait des échecs confus dans tous les autres fichiers de test au lieu d'un message clair.

## Lancer les tests

Depuis la racine du projet :

```bash
./launch.sh tests
```

Le lanceur Python peut aussi être appelé directement :

```bash
python3 tests/run_all_tests.py
```

Resultat attendu :

```text
Summary: 24 passed, 0 failed
```

Le code retour est :

- `0` si tous les tests passent;
- `1` si au moins un test echoue;
- `2` si aucun test n'est trouve.

## Limites actuelles

Ces tests sont des tests statiques et locaux. Ils ne valident pas encore :

- la presence reelle de `llama-server`;
- la detection du GPU NVIDIA;
- le chargement du modele GGUF;
- la consommation VRAM/RAM;
- le debit en tokens par seconde;
- la reponse reelle de `/v1/models`;
- une requete complete depuis Hermes sur Windows.

Ces verifications devront etre ajoutees dans une suite d'integration separee, executee uniquement sur la machine Linux cible avec le service et le modele installes.

Les tests ajoutes ici couvrent la regression de chemin et les prerequis de service afin d'eviter qu'un changement casse le lancement du backend ou la configuration de connexion a distance sans detection immediate.

## Regle de validation

Une modification du service ou de la configuration doit commencer par :

```bash
python3 tests/run_all_tests.py
```

Ensuite seulement, les tests d'integration pourront etre executes sur la machine reelle. Les tests d'integration ne doivent pas modifier le compte administrateur ni le boot graphique global.

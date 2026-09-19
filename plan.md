# Plan de développement — Linux Hermes Agent Launcher

## 1. Objectif produit

Créer un environnement Linux dans lequel seul le compte `llmuser` devient une boîte LLM headless, pour qu’un client Windows exécutant Hermes Agent puisse envoyer les requêtes vers ce compte via une API OpenAI-compatible.

Le but n’est pas de faire un serveur “beau” ni un poste de travail complet. Le but est de maximiser la puissance d’inférence sur la machine Linux en laissant au minimum la charge système hors modèle.

En pratique :
- Windows reste le poste principal où Hermes Agent est utilisé.
- `llmuser` est le seul compte Linux dédié au serveur LLM.
- Le compte administrateur et les autres comptes de la maison gardent leur bureau, leurs réglages et leur usage normal.
- La communication se fait via le réseau local.
- Le service LLM est lancé automatiquement sous `llmuser`, reste stable, et consomme le plus possible de ressources pour la génération.

---

## 2. Vision d’architecture

```text
┌──────────────────────────────────────────────────────────────────────┐
│                        PC Windows (Hermes Agent)                     │
│                                                                      │
│  Hermes Agent                                                      │
│  - orchestration                                                   │
│  - outils / prompts                                                │
│  - logique applicative                                             │
│                                                                      │
│  HTTP / REST / OpenAI-compatible                                    │
│  base_url = http://<IP_LINUX>:8080/v1                               │
└───────────────────────────────┬──────────────────────────────────────┘
                                │ LAN / réseau local
                                │
                                ▼
┌──────────────────────────────────────────────────────────────────────┐
│               PC Linux (poste normal + compte llmuser)               │
│                                                                      │
│  +-------------------------+     +-------------------------------+  │
│  | Compte administrateur   |     | Compte llmuser                 |  │
│  | - bureau graphique      |     | - session headless             |  │
│  | - usage normal          |     | - terminal/script uniquement   |  │
│  | - non modifié           |     | - llama-server + modèle       |  │
│  +-------------------------+     +---------------+---------------+  │
│                                                  │                  │
│                                                  ▼                  │
│                                   +-------------------------------+  │
│                                   | systemd                       |  │
│                                   | User=llmuser                  |  │
│                                   | auto-start / restart          |  │
│                                   +---------------+---------------+  │
│               │                                                       │
│               ▼                                                       │
│  +-------------------------+                                        │
│  | llama.cpp / llama-server|                                        │
│  |  - model GGUF           |                                        │
│  |  - OpenAI compatible    |                                        │
│  |  - host 0.0.0.0         |                                        │
│  |  - port 8080            |                                        │
│  +------------+------------+                                        │
│               │                                                       │
│               ▼                                                       │
│  +-------------------------+                                        │
│  | GPU / CPU / RAM tuning  |                                        │
│  |  - GPU dense layers     |                                        │
│  |  - CPU offload experts  |                                        │
│  |  - KV cache optimized    |                                        │
│  +-------------------------+                                        │
│                                                                      │
│  Le compte llmuser n’utilise pas de bureau graphique                  │
│  Le compte administrateur et les autres utilisateurs ne sont pas      │
│  transformés en comptes serveur                                        │
└──────────────────────────────────────────────────────────────────────┘
```

---

## 3. Principes de conception

### Règle fonctionnelle importante

Au redémarrage, la machine Linux doit automatiquement retrouver le mode graphique (`graphical.target`).

Cela ne signifie pas que le service LLM doit dépendre d’un écran visible. Au contraire, le modèle doit continuer à tourner en arrière-plan via `systemd`, tandis que la machine reste exploitable en mode standard pour les tâches de maintenance, le debug local, ou la gestion du système.

Le mode headless ne doit pas être la configuration par défaut du boot. Il doit rester un mode de dépannage ou de maintenance ponctuelle, pas la règle stable du système.

### 3.1 Isolation du compte `llmuser`

`llmuser` est le seul compte concerné par le runtime LLM :
- `systemd` lance `llama-server` avec `User=llmuser`;
- le modèle, les logs et la configuration du service lui appartiennent;
- aucune session graphique n’est nécessaire pour `llmuser`;
- le compte administrateur et les autres comptes ne lancent pas le LLM et ne reçoivent pas sa configuration.

Cette isolation concerne les processus, fichiers, permissions et sessions. Elle ne peut pas rendre privés les réglages du noyau Linux : `sysctl`, GRUB, governor CPU, swap et certains réglages du pilote GPU sont globaux. Le projet ne doit donc pas les modifier automatiquement en prétendant qu’ils ne touchent que `llmuser`.

### 3.2 Priorité absolue : performance d’inférence

Le Linux doit servir le modèle, sans sacrifier la stabilité du système ni la gestion du poste.

Cela signifie :
- garder un boot standard en mode graphique;
- lancer le serveur LLM en arrière-plan via `systemd`;
- limiter les processus du compte `llmuser` au serveur et à ses outils;
- éviter les applications graphiques dans la session `llmuser`;
- réserver la VRAM au modèle via les paramètres de `llama-server`;
- régler les threads, le cache et l’offload dans le service, sans modifier les comptes voisins.

### 3.3 L’API doit être simple et stable

Le système doit exposer une interface REST OpenAI-compatible sur le port 8080.

Cela permet à Hermes sur Windows de ne pas devoir changer d’architecture logicielle :
- base_url pointe vers le Linux;
- le client pense parler à un LLM standard compatible OpenAI;
- la machine Linux fait le travail de génération.

### 3.4 La session `llmuser` doit être ultra-minimaliste

C’est une boîte de calcul séparée à l’intérieur du PC, pas un poste de travail pour `llmuser`.

Tout ce qui n’est pas utile à :
- démarrer le modèle;
- surveiller le service;
- gérer les logs;
- maintenir la connexion réseau;

doit être supprimé ou désactivé pour la session et les processus de `llmuser`, sans désactiver les outils nécessaires aux autres utilisateurs.

---

## 4. Cible technique

### 4.1 Machine Linux cible

- Ubuntu standard avec `graphical.target` conservé pour le compte administrateur
- SSH actif
- compte humain dédié `llmuser`, utilisé comme compte headless
- service systemd dédié au modèle avec `User=llmuser`
- GPU NVIDIA prioritaire
- mémoire vive suffisante pour le CPU offload des experts MoE

### 4.2 Modèle de calcul

Le moteur principal doit être **llama.cpp**, lancé par son serveur HTTP
**`llama-server`**. `llama-server` est le binaire réseau de llama.cpp, pas un
deuxième moteur.

Pourquoi :
- modèle GGUF chargé directement;
- contrôle fin des couches envoyées vers le GPU avec `--gpu-layers`;
- contrôle du cache KV et des threads CPU;
- API OpenAI-compatible pour Hermes;
- moins de couches logicielles et moins de consommation hors inference;
- meilleur gestion du MoE;
- tuning plus précis sur VRAM / RAM;
- plus adapté à une configuration 12 Go VRAM + CPU offload.

Limite à respecter : llama.cpp ne garantit pas un découpage expert-par-expert
parfait pour tous les modèles MoE. L'offload se règle principalement par
couches et doit être validé par des mesures réelles. Le réglage recommandé ne
sera accepté qu'après mesure de la VRAM, de la RAM, des tokens/s, de la latence
et de la stabilité sur le contexte Hermes.

### 4.3 Modèle de déploiement

Le flux de travail idéal :
1. Ubuntu démarre normalement en mode graphique pour le compte administrateur.
2. systemd démarre automatiquement le service sous `llmuser`.
3. la session `llmuser` reste sans bureau et n’est ouverte que pour lancer un terminal ou un script de gestion.
4. Hermes sur Windows appelle le endpoint distant.
5. `llmuser` répond avec les tokens générés.
6. si le modèle doit changer, le service est redémarré avec une nouvelle configuration.

Chaîne d'exécution du LLM :

```text
llmuser -> systemd -> llama-server -> llama.cpp -> GPU / CPU / RAM
```

---

## 5. Plan de développement par phases

### Phase 1 — Base système minimale

Objectif : rendre la machine Linux stable, propre et compatible avec un usage de backend LLM, tout en garantissant un démarrage rétabli automatiquement en mode graphique.

Tâches :
- vérifier que le compte administrateur et les autres comptes restent inchangés;
- configurer `llmuser` comme compte headless dédié;
- configurer Ubuntu pour qu’au reboot le système reste en `graphical.target`;
- vérifier que le service LLM peut rester actif en arrière-plan sans dépendre d’un écran;
- activer SSH pour la gestion à distance;
- vérifier la présence GPU NVIDIA;
- assigner la bonne configuration de pilotes;
- réduire les processus de fond inutiles;
- installer les dépendances minimales de llama.cpp.

Livrables :
- machine Linux fonctionnelle en mode standard au reboot;
- accès SSH fonctionnel;
- service LLM continu en arrière-plan;
- GPU visible par le système;
- état système stable avant lancement du modèle.

---

### Phase 2 — Service LLM automatique

Objectif : créer un service durable qui démarre sans intervention manuelle.

Le projet inclut désormais un helper d’auto-détection et d’installation de `llama-server` pour éviter d’avoir à installer manuellement le binaire avant le lancement du service.

Tâches :
- détecter si `llama-server` est déjà présent sur le système;
- sinon installer automatiquement le binaire depuis le dépôt source de llama.cpp;
- placer le binaire dans un chemin standard (`/usr/local/bin/llama-server` ou équivalent);
- générer une unit systemd dédiée;
- configurer `ExecStart` avec le bon modèle GGUF;
- exposer le serveur sur `0.0.0.0:8080`;
- redémarrer automatiquement en cas de crash;
- stocker les logs dans un dossier lisible via SSH;
- tester le endpoint local en curl.

Livrables :
- serveur LLM lancé via systemd;
- API accessible localement;
- service stable après reboot ou crash;
- installation automatique du binaire `llama-server` quand il est absent.

### 2.3 Dossier de modèles et logs

Objectif : garantir que le service LLM dispose d’un dossier de modèles et de logs correctement créé, avec les permissions adaptées au compte `llmuser`, sans intervention manuelle de l’utilisateur.

Problème réel :
- le dossier `/opt/models` ou `$HOME/.local/models` peut être absent;
- le dossier de logs systemd peut être absent;
- les permissions sur les fichiers peuvent être incorrectes;
- le service `llama-server` ne peut pas démarrer proprement si le dossier du modèle ou les logs ne sont pas accessibles au compte `llmuser`.

À automatiser :
- vérifier si `MODEL_DIR` existe;
- le créer avec les bons droits et les bons propriétaires;
- créer le dossier de logs (`/opt/hermes-llm/logs` ou équivalent) automatiquement;
- donner les permissions nécessaires au compte `llmuser`;
- gérer les permissions de lecture/écriture du modèle et des logs pour `llama-server`;
- vérifier que le dossier du modèle contient bien un `.gguf` exploitable avant de lancer le service.

Règle de conception : le programme doit s’assurer que les dossiers de runtime sont propres avant toute tentative de service. L’utilisateur ne doit plus avoir à créer ces chemins manuellement ni à corriger des permissions insuffisantes.

### 2.4 Génération cohérente du fichier `.env`

Le point 2.6 de l’automatisation est désormais couvert par un script dédié de bootstrap de configuration.

Objectif : générer un fichier `.env` cohérent avant toute tentative de démarrage du service.

Ce script vérifie automatiquement :
- que `MODEL_DIR` existe et est écrit correctement ;
- que `LISTEN_PORT` reste sur la valeur compatible 8080 ;
- que `CTX_SIZE` reste à `73728` ;
- que `MODEL_FILENAME` correspond bien à un fichier `.gguf` réellement présent ;
- que le fichier de config est réécrit avec les valeurs actives du runtime.

Le flux cible est : `./launch.sh bootstrap`.

### 2.5 Installation et validation du service systemd

Le point Priorité 4 est désormais couvert par un bootstrap systemd dédié.

Objectif : installer le service `llama-ornith.service`, associer le bon fichier `.gguf`, et vérifier qu’il devient actif sans intervention manuelle.

Ce script vérifie automatiquement :
- que le serveur `llama-server` est installé ;
- que le fichier du modèle existe bien dans `MODEL_DIR` ;
- que le service est écrit au bon chemin `/etc/systemd/system/llama-ornith.service` ;
- que `systemctl daemon-reload` puis `enable --now` sont exécutés ;
- que le service est bien actif avec `systemctl is-active --quiet` ;
- qu’un message clair est remonté si le backend ne démarre pas.

Le flux cible est : `./launch.sh systemd`.

### 2.6 Validation de l’API OpenAI-compatible locale

Objectif : s’assurer que le backend est réellement serviceable et répond bien sur les endpoints attendus par Hermes.

Le script de validation locale vérifie :
- `GET http://127.0.0.1:8080/v1/models` renvoie HTTP 200 ;
- `POST http://127.0.0.1:8080/v1/chat/completions` renvoie HTTP 200 ;
- le payload envoyé est bien compatible OpenAI ;
- l’utilisateur reçoit un message clair si le service est installé mais pas encore prêt.

Le flux cible est : `./launch.sh api`.

### Phase 2.5 — Bootstrap automatique sans friction pour l’utilisateur

Objectif : que la personne qui utilise le programme n’ait plus à comprendre les détails techniques du format de modèle, du path GGUF, du dépôt Hugging Face, ni de la conversion `.safetensors` vers `.gguf`.

Ce point est maintenant une exigence centrale du projet. L’utilisateur ne doit pas voir ni manipuler les concepts suivants :
- le nom exact du fichier `.gguf`;
- l’extension `.gguf` ou le modèle configuré manuellement;
- la différence entre un dépôt HF standard et un dépôt GGUF prêt à l’emploi;
- l’étape de conversion `convert_hf_to_gguf.py`;
- la nécessité de savoir où placer le fichier sur le disque;
- la distinction entre `MODEL_DIR`, `MODEL_FILENAME` et le chemin `llama-server`.

Le logiciel doit fournir un flux zéro-complexité :

1. si `llama-server` est absent, l’application l’installe automatiquement;
2. si le dossier de modèles est vide, l’application détecte automatiquement le besoin d’un GGUF;
3. si le dépôt choisi est un dépôt HF au format `safetensors` (comme le repo Ornith réel), le programme doit automatiquement choisir la bonne stratégie :
   - télécharger un GGUF officiel compatible, si disponible;
   - ou lancer la conversion depuis le dépôt HF vers GGUF via `llama.cpp`;
4. une fois le `.gguf` prêt, le programme écrit le `MODEL_FILENAME` dans la configuration sans demander à l’utilisateur de taper un nom de fichier;
5. le service est relancé automatiquement avec le bon fichier;
6. l’API est vérifiée localement sans que l’utilisateur ait à exécuter des commandes shell avancées.

Règle de conception : la seule interaction utilisateur acceptée est une simple commande comme `./launch.sh install` ou `./launch.sh start`. Tous les détails techniques sont gérés par le programme.

Ce point est indispensable pour éviter le type de blocage actuel : un dépôt HF contenant des `.safetensors` ne suffit pas pour `llama.cpp`, et l’utilisateur ne doit pas être contraint de savoir qu’il faut convertir le modèle ou trouver un binaire GGUF prêt à l’emploi.

### État réel du projet (présent dans l’environnement de travail)

Le dépôt a bien une couche de validation qui vérifie les prérequis, mais l’environnement exécutif courant n’est pas encore prêt à démarrer le modèle réel :
- `llama-server` est absent;
- le dossier de modèles n’existe pas encore;
- le fichier GGUF demandé par la config n’est pas présent;
- le service ne peut donc pas servir de backend complet tant que le binaire et le modèle sont installés.

Le helper d’auto-install est donc une étape de robustesse et de fiabilité, mais il ne remplace pas la présence du modèle GGUF réel dans le dossier cible. Le cycle correct est :
1. détecter / installer `llama-server`;
2. préparer le modèle GGUF automatiquement;
3. copier le GGUF vers le dossier de modèles;
4. configurer `.env` sans l’intervention utilisateur;
5. lancer le service;
6. tester l’API OpenAI-compatible locale puis distante.

---

### Phase 3 — Intégration Hermes / Windows

Objectif : faire que le client Windows utilise la machine Linux comme backend LLM.

Tâches :
- configurer la base URL Hermes vers le Linux;
- valider le endpoint `/v1` OpenAI-compatible;
- vérifier `hermes model list` et `hermes connect`;
- tester un prompt simple complet;
- sécuriser le port en LAN avec filtrage réseau.

Livrables :
- Hermes fonctionne sans modèle local;
- toutes les requêtes transitent par le serveur Linux;
- la réponse est bien renvoyée à Hermes.

---

### Phase 4 — Performance et tuning

Objectif : maximiser la capacité d’inférence avec les ressources disponibles.

Tâches :
- configurer le bon modèle GGUF;
- s’assurer du bon split GPU/CPU pour le MoE;
- activer les optimisations de cache KV;
- vérifier les flags de quantification;
- tester des prompts de tailles différentes;
- monitorer latence, vitesse de génération et stabilité.
- comparer les variantes de `--gpu-layers` sans modifier les autres comptes;
- retenir uniquement une configuration validée par mesures réelles.

Livrables :
- benchmark minimal de performance;
- configuration recommandée;
- procédure de diagnostic et d'arrêt propre en cas de saturation RAM; aucune quantification dégradée.
- tableau de mesures VRAM / RAM / tokens par seconde / latence;

---

### Phase 5 — Sécurité et robustesse

Objectif : rendre le système exploitable sans risque pour le réseau local.

Tâches :
- restreindre les accès réseau au client Windows;
- configurer la clé API si besoin;
- bloquer toute exposition Internet inutile;
- installer le watchdog Internet avec NetworkManager;
- vérifier périodiquement la connectivité et demander une reconnexion automatique;
- documenter l’arrêt, le redémarrage, et le switch de modèle;
- prévoir une procédure de retour en mode desktop si besoin.

Livrables :
- configuration sûre;
- service fiable en environnement LAN;
- service `hermes-internet-watchdog.service` opérationnel;
- mécanisme de reprise en cas de panne.

---

## 6. Spécifications de qualité

### 6.1 Fonctionnelles
- le Linux redémarre automatiquement en mode graphique;
- Hermes sur Windows peut appeler le serveur LLM distant;
- le service LLM reste actif en arrière-plan sans écran;
- les réponses sont renvoyées correctement;
- le service redémarre sans intervention manuelle;
- la connexion Internet est surveillée et une reconnexion est tentée automatiquement;
- le système accepte le changement de modèle facilement.

### 6.2 Non fonctionnelles
- CPU et RAM essentiellement dédiés au modèle;
- faible latence de réseau local;
- logs exploitables en SSH;
- redémarrage rapide;
- configuration simple et reversible.

### 6.3 Sécurité
- uniquement le client Windows doit pouvoir accéder au port LLM;
- pas d’exposition publique;
- aucune clé secrète commitée dans le dépôt;
- services non nécessaires désactivés.

---

## 7. Risques et contraintes

### Risque principal : saturation mémoire

Le point critique est le rapport entre :
- VRAM disponible;
- RAM système;
- offload CPU des experts;
- contexte demandé.

Le système doit être conçu pour fonctionner avec des pesos quantifiés et un offload intelligent, sans faire exploser la RAM ou la VRAM.

### Risque secondaire : contexte trop long

Hermes impose un contexte minimum élevé. Le système doit donc être dimensionné pour un contexte de travail sérieux, sans débordement ni crash de génération.

### Risque opérationnel : service non stable

Le serveur doit être lancé via systemd et non via un shell interactif. L’exécution manuelle est acceptable pour le test, mais pas pour la production.

### Risque réseau : coupures fréquentes

Le watchdog peut relancer une interface via NetworkManager, mais il ne peut pas
réparer une panne du routeur, du fournisseur ou du matériel. Il doit journaliser
les échecs et continuer ses tentatives sans modifier le boot graphique ni les
comptes utilisateurs.

---

## 8. Critères d’acceptation

Le projet est considéré comme réussi lorsque :

1. Le compte administrateur démarre normalement en mode graphique.
2. `llmuser` n’utilise pas de bureau graphique.
3. Le service LLM est lancé automatiquement.
4. Le binaire `llama-server` est détecté ou installé automatiquement si absent.
5. Le modèle GGUF est présent dans le dossier de modèles configuré.
6. Hermes sur Windows dialogue avec le serveur Linux via `base_url`.
7. Le modèle répond correctement aux requêtes.
8. Le watchdog réseau vérifie Internet et tente une reconnexion.
9. Les ressources système restent compatibles avec l’inférence.
10. La configuration est simple à reproduire.
11. Le système peut être remis en mode desktop si nécessaire.

---

## 9. Plan opérationnel de mise en œuvre

### Étape 1 — construire la base
- conserver Ubuntu standard et le boot graphique;
- configurer `llmuser` comme compte headless;
- configurer SSH;
- vérifier les pilotes GPU;
- préparer les dossiers de modèles et logs.

### Étape 2 — installer le moteur
- vérifier ou installer automatiquement `llama-server` via le helper dédié;
- compiler ou installer llama.cpp si nécessaire;
- télécharger le modèle GGUF cible;
- valider le lancement local de `llama-server`.

### Étape 3 — sécuriser le service
- créer le service systemd;
- vérifier le restart automatique;
- vérifier les logs;
- activer le bon port réseau.

### Étape 4 — brancher Hermes
- configurer le point d’entrée sur le Linux;
- tester les appels API;
- valider les prompts réels.

### Étape 5 — optimiser
- analyser CPU/GPU/RAM;
- ajuster le split GPU/CPU;
- documenter l'échec propre et le diagnostic mémoire; aucune quantification dégradée;
- fixer les paramètres “best stable”.

---

## 10. Recommandation finale

Le bon design est celui d’un serveur LLM autonome porté par le seul compte `llmuser`, sans interface graphique pour ce compte, avec la seule fonction de répondre aux requêtes du client Hermes.

L’architecture la plus solide est :
- compte `llmuser` headless;
- compte administrateur et autres comptes conservés en mode normal;
- service systemd;
- `llama.cpp` comme moteur principal;
- API OpenAI-compatible sur port 8080;
- Hermes sur Windows comme interface utilisateur;
- réseau local uniquement.

C’est la voie la plus simple, la plus performante et la plus stable pour maximiser l’utilisation du Linux comme backend de raisonnement LLM.

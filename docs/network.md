# Surveillance de la connexion Internet

## Objectif

La box Linux doit verifier regulierement que la connexion Internet fonctionne. En cas de coupure, elle demande a NetworkManager de reactiver le reseau et de reconnecter les interfaces disponibles.

Cette fonction est distincte du serveur LLM :

- le service LLM tourne sous `llmuser`;
- le watchdog reseau est un service systeme, car la connexion reseau est globale a Ubuntu;
- le watchdog ne modifie ni le boot graphique ni les autres comptes utilisateurs;
- les actions de reconnexion peuvent momentanement affecter toutes les sessions, ce qui est inevitable pour une reconnexion reseau systeme.

## Configuration

Dans `config/.env` :

```bash
INTERNET_CHECK_URL=https://connectivitycheck.gstatic.com/generate_204
INTERNET_CHECK_INTERVAL=30
NETWORK_INTERFACE=
```

`NETWORK_INTERFACE` peut contenir un nom comme `wlan0` ou `enp3s0`. S'il est vide, le watchdog demande a NetworkManager de reconnecter toutes les interfaces Wi-Fi ou Ethernet non connectees.

## Installation

NetworkManager et `curl` doivent etre disponibles :

```bash
sudo ./scripts/internet-watchdog.sh install
```

Le service est ensuite lance automatiquement a chaque demarrage :

```text
hermes-internet-watchdog.service
```

Il attend le reseau avec `network-online.target`, verifie l'URL configuree toutes les 30 secondes et redemarre automatiquement s'il s'arrete.

## Commandes

Tester Internet une seule fois :

```bash
./scripts/internet-watchdog.sh check
```

Demander une reconnexion NetworkManager :

```bash
sudo ./scripts/internet-watchdog.sh reconnect
```

Afficher l'etat du service :

```bash
sudo ./scripts/internet-watchdog.sh status
```

## Limites

Le watchdog ne peut pas reparer :

- une panne du fournisseur Internet;
- une panne physique du routeur;
- un mot de passe Wi-Fi incorrect;
- un pilote reseau absent;
- une interface desactivee au niveau materiel.

Dans ces cas, il journalise l'echec et continue ses tentatives. Les logs sont ecrits par defaut dans `/var/log/hermes-internet-watchdog.log`.

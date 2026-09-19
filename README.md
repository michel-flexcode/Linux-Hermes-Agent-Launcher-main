# Linux Hermes Agent Launcher

Single-source project documentation for the local inference backend.

## Canonical rule

This repository must keep one canonical workflow and one canonical branch:

- main
- tracking origin/main

## Quickstart

### Admin host

```bash
./launch.sh quickstart
```

### Local-only mode

```bash
./launch.sh bootstrap
./launch.sh model
./launch.sh api
```

> The quickstart installs host-level runtime pieces and therefore requires root or sudo. A non-admin user can still bootstrap and validate locally, but cannot install the system-level service.

## Main commands

```bash
./launch.sh help
./launch.sh menu
./launch.sh setup
./launch.sh bootstrap
./launch.sh model
./launch.sh install
./launch.sh start
./launch.sh stop
./launch.sh restart
./launch.sh status
./launch.sh models
./launch.sh api
./launch.sh internet
./launch.sh reconnect
./launch.sh watchdog
./launch.sh tests
```

## Project goal

Expose an OpenAI-compatible API from a Linux host for Hermes Agent.

```text
Windows Hermes Agent -> LAN -> Linux host -> llama.cpp -> GGUF model
```

## Real constraints

- Setup and validation can run without root.
- systemd service installation requires sudo/root.
- This repo must not pretend there is a single mode for both local validation and host installation.
- Keep one clean documentation set and one clean branch policy.

## Current status

The repo is intentionally strict about the production dependency:

- the code is valid
- the tests pass
- admin privileges are required for the systemd service
- the project must remain simple and coherent

## Files to keep canonical

- [launch.sh](launch.sh)
- [scripts/](scripts/)
- [config/](config/)
- [tests/](tests/)
- [docs/](docs/)
- [plan.md](plan.md)

This README and the quickstart guide are the two canonical references. Any duplicate or contradictory doc should be treated as dead noise.

Le service peut être `disabled` sans modifier le boot graphique ni les autres comptes. Le compte
administrateur conserve son environnement Ubuntu standard.

## Arborescence

```
Linux-Hermes-Agent-Launcher/
├── README.md
├── launch.sh                  (point d'entrée principal)
├── config/
│   ├── .env.example
│   └── secrets.env.example         (clé API, NE JAMAIS committer)
├── scripts/
│   ├── launcher.sh                 (menu interactif)
│   ├── pre-start-optimizer.sh      (validation du boot + configuration)
│   ├── llama-ornith-serve.sh       (unité systemd du serveur LLM)
│   ├── internet-watchdog.sh        (surveillance et reconnexion réseau)
│   └── giga-serve.sh               (gestion start/stop/switch/status)
└── docs/
    └── config-reference.md         (détail complet des flags & mémoire)
```

# Quickstart

## Commande unique (recommandé)

```bash
git clone https://github.com/michel-flexcode/Linux-Hermes-Agent-Launcher-main.git
cd Linux-Hermes-Agent-Launcher-main
./launch.sh quickstart
```

> `./launch.sh quickstart` nécessite des droits admin (`sudo` / `root`) car il installe le service système et les dépendances hôte.
>
> Sans sudo, tu peux toujours faire le bootstrap local et valider l'API, mais pas installer le service système.

## Workflow canonique

### Sur une machine admin

```bash
./launch.sh quickstart
```

### Validation locale sans sudo

```bash
./launch.sh bootstrap
./launch.sh model
./launch.sh api
```

## Séquence de commandes

```bash
./launch.sh setup
./launch.sh bootstrap
./launch.sh model
./launch.sh install
./launch.sh api
```

## Commandes de statut

```bash
./launch.sh status
./launch.sh start
./launch.sh stop
./launch.sh restart
./launch.sh models
```

## Références

- [../README.md](../README.md)
- [../plan.md](../plan.md)
- [../docs/tests.md](../docs/tests.md)

La documentation doit rester courte et cohérente. Ne pas conserver de versions contradictoires.


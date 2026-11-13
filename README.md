# ansible-linux-lab

Configuration automatisée d'un serveur Ubuntu 24.04 avec Ansible, dans un petit lab de deux machines virtuelles (Multipass).
Projet personnel d'apprentissage : **lab jetable, pas une configuration de production.**

## Objectif

Décrire dans un playbook l'état voulu d'un serveur, l'appliquer automatiquement, puis le prouver :

- **idempotence** : une 2ᵉ exécution ne change rien (`changed=0`) ;
- **détection de dérive** : `--check --diff` montre les écarts sans rien modifier ;
- **reconstruction** : une machine détruite est remise dans l'état voulu par une seule commande.

## Architecture

```text
 PC (Kali Linux)                  réseau privé Multipass
 ┌──────────────────┐  multipass  ┌──────────────┐   SSH (clé)   ┌──────────────┐
 │ Git, GitHub CLI  │ ──────────► │ ctrl         │ ────────────► │ target       │
 │ dépôt du projet  │ ◄─ mount ─► │ Ansible      │    Ansible    │ Ubuntu 24.04 │
 └──────────────────┘             │ Ubuntu 24.04 │               │ à configurer │
                                  └──────────────┘               └──────────────┘
```

- `ctrl` : machine de contrôle (Ansible), Ubuntu 24.04.
- `target` : serveur configuré, Ubuntu 24.04. Aucun agent : Ansible s'y connecte en SSH et utilise le Python déjà présent.
- Le dépôt vit sur le PC et est partagé dans `ctrl` par `multipass mount` : Ansible s'exécute dans `ctrl`, les commits et les push se font depuis le PC.
- Connexion SSH par clé. La clé privée du lab est créée dans `ctrl` et n'en sort jamais ; seule la clé publique est copiée sur `target`.

## Ce que fait le playbook

| Domaine | Détail |
|---|---|
| Paquets | curl, cron, htop, nginx, ufw, vim |
| Utilisateurs | compte `ops` avec clé SSH et `sudo` (fichier validé par `visudo`) |
| SSH | mot de passe et connexion root désactivés (fichier `00-` validé par `sshd -t`, redémarrage par handler) |
| Pare-feu | UFW : entrant refusé sauf 22/tcp et 80/tcp (SSH autorisé **avant** l'activation) |
| Web | nginx, page générée par un modèle Jinja2 |
| Sauvegarde | archive de `/etc` chaque nuit à 02:30, 7 jours conservés (cron), archive lisible par root seulement |
| Vérifications | le playbook contrôle lui-même la configuration SSH effective (`sshd -T`) et le contenu de la page web |

## Arborescence

```text
.
├── ansible.cfg                  # inventaire par défaut, réglages du lab
├── site.yml                     # le playbook (16 tâches + 1 handler)
├── group_vars/all.yml           # variables : compte, paquets, horaire de sauvegarde
├── inventory/hosts.ini.example  # modèle d'inventaire (le vrai hosts.ini n'est pas versionné)
├── templates/index.html.j2      # page d'accueil nginx
├── files/backup-etc.sh          # script de sauvegarde déployé sur la cible
└── docs/                        # journaux des exécutions (preuves)
```

## Utilisation

```bash
cp inventory/hosts.ini.example inventory/hosts.ini   # puis y mettre l'adresse de la VM cible
ansible servers -m ansible.builtin.ping
ansible-playbook site.yml                            # application
ansible-playbook site.yml --check --diff             # simulation, sur une machine déjà configurée
ansible-playbook site.yml --tags web                 # ne rejouer qu'une partie
```

Contrôles avant exécution : `ansible-playbook site.yml --syntax-check` et `ansible-lint site.yml` (0 échec, profil `production`).

## Résultats

Résultats réels, journaux dans `docs/` :

| Preuve | Résultat | Journal |
|---|---|---|
| 1ʳᵉ exécution (machine neuve) | `ok=18 changed=12 unreachable=0 failed=0` | `docs/run-1.log` |
| 2ᵉ exécution (idempotence) | `ok=17 changed=0 unreachable=0 failed=0` | `docs/run-2.log` |
| Dérive volontaire (page supprimée, `PermitRootLogin yes`) | détectée par `--check --diff` : `changed=3`, rien de modifié ; corrigée à l'exécution suivante, puis retour à `changed=0` | `docs/drift-check.log` |
| Reconstruction de `target` de zéro | VM supprimée et recréée, configuration complète en **13,7 s** (`real`, playbook seul, hors création de la VM), puis `changed=0` | `docs/rebuild.log` |

La reconstruction est rapide parce que l'image Ubuntu 24.04 contient déjà la plupart des paquets : seuls `nginx` et `nginx-common` ont été installés.

## Versions

Ansible 9.2.0 (ansible-core 2.16.3, paquet Ubuntu 24.04), ansible-lint 6.17.2, Ubuntu 24.04.5 LTS, OpenSSH 9.6, nginx 1.24.0, Multipass 1.17.0 (hôte Kali Linux).

## Limites (lab uniquement)

- `sudo` sans mot de passe (`NOPASSWD:ALL`) : pratique en lab, à proscrire en production.
- `host_key_checking = False` : les VM jetables changent de clé d'hôte à chaque reconstruction. En production, les clés d'hôte doivent être vérifiées.
- Une seule clé SSH partagée, sans phrase de passe ; pas de supervision ; pas de sauvegarde hors de la machine.
- Le playbook n'a été exécuté que dans ce lab.

## Ce que j'ai appris et problèmes rencontrés

- **Image Multipass corrompue.** Le premier `multipass launch` a échoué : l'empreinte SHA-256 de l'image ne correspondait pas. L'empreinte attendue était bien celle publiée par Ubuntu : c'était donc mon téléchargement qui était abîmé. Correction : suppression de l'image en cache, nouveau téléchargement. Même principe que le contrôle `sha256sum -c` des fichiers du projet.
- **`multipass` introuvable sous Kali.** Le paquet snapd n'ajoute pas `/snap/bin` au `PATH` de zsh. Correction : ligne `export PATH="$PATH:/snap/bin"` dans `~/.zshrc`.
- **Un code HTTP 200 ne prouve pas que la page est la bonne.** Pendant le test de dérive, la page d'accueil supprimée, nginx répondait toujours `200` : il servait sa page par défaut (`index.nginx-debian.html`, 3ᵉ nom de la directive `index`). C'est pour cela que le playbook vérifie le **contenu** de la page, pas seulement la réponse.
- **Une vérification qui avertit sans arrêter.** Lors de la reconstruction, j'ai collé un bloc sans remplacer l'adresse : le contrôle a affiché `ERREUR`, mais `cmd || echo` n'arrête pas la suite, et l'inventaire a reçu un texte au lieu d'une IP (`Could not resolve hostname`). Leçon : enchaîner avec `&&` pour que la modification n'ait lieu que si le contrôle réussit.
- **Coupure de courant en cours de projet.** Les VM ont redémarré seules avec les mêmes adresses et le partage de dossier ; aucun fichier n'était abîmé (empreintes vérifiées). Depuis, je commite et pousse à chaque étape.

## Pour aller plus loin

- Découper `site.yml` en rôles (`roles/ssh`, `roles/web`...).
- Lancer `ansible-lint` automatiquement à chaque `push` (GitHub Actions).
- Ajouter une 2ᵉ cible dans l'inventaire et utiliser `--limit`.
- Remplacer `NOPASSWD:ALL` par une liste de commandes autorisées, et une clé par administrateur.
- Sauvegarde envoyée hors de la machine.
- Script qui met à jour l'inventaire à partir de `multipass list`.

## Origine

Projet réalisé à partir d'un guide pas à pas de référence, que j'ai suivi, compris puis adapté (dépôt sur le PC partagé avec la VM de contrôle, journal de reconstruction, contrôles supplémentaires).

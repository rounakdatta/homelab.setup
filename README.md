![homelab.setup-logo](homelab.setup_logo.png)

This repository hosts all the playbooks required to deploy and run my homelab. You have to bring your own hardware, Linux operating system, configuration secrets and *data* though.

My homelab is a single-node x64 (previously ARM) machine, and applications are deployed containerized via Hashicorp Nomad. Tailscale takes care of all the networking required for administration and deployments. Cloudflare Tunnels help in exposing the services to the internet.

## List of self-hosted applications

| App            | Purpose                                        | Project homepage                       |
|----------------|------------------------------------------------|----------------------------------------|
| MySQL          | Database (common dependency for multiple apps) | https://dev.mysql.com/downloads/mysql/ |
| Firefly-III    | Personal finance                               | https://www.firefly-iii.org/           |
| Bookstack      | Documentation & Diary                          | https://www.bookstackapp.com/          |
| Vikunja        | Todo list                                      | https://vikunja.io/                    |
| Nextcloud      | Google Drive alternative                       | https://nextcloud.com/                 |
| Webtrees       | Family tree (genealogy)                        | https://www.webtrees.net/index.php/en/ |
| Photoprism     | Google Photos alternative                      | https://photoprism.app/                |
| Audiobookshelf | Audiobook server (Audible alternative)         | https://www.audiobookshelf.org/        |
| Kavita         | Ebook reader (think Apple Books on the web)    | https://www.kavitareader.com/          |
| Duplicati      | Encrypted, incremental backups                 | https://www.duplicati.com/             |
| NTFY           | Push Notifications REST service                | https://ntfy.sh/                       |
| Cronicle       | Powerful cron scheduler                        | http://cronicle.net/                   |
| Mailpile       | Web archive for email                          | https://www.mailpile.is/               |
| Miniflux       | RSS reader                                     | https://miniflux.app/                  |
| Metabase       | SQL / analytics interface                      | https://www.metabase.com/              |
| n8n            | Scheduled and on-demand DAGs and workflows     | https://n8n.io/                        |

## Architecture

Hashicorp Nomad is undoubtedly a very good orchestrator of services and the declarative design of deployments make it even easier to administer. I also have setup a Caddy webserver as an ingress gateway. There's one Cloudflare Tunnel for each application, and that channels the requests to directly hit the Caddy endpoints. A simple diagram to illustrate the lifecycle of requests is:

![request-lifecycle](https://i.imgur.com/VgvjzC6.png)

The way the Ansible playbook is structured makes it super-easy to onboard a new application. Look at some of the past pull-requests to understand how it's only about copy-pasting, filling up templates and adding some secrets.

## Philosophy

The project was born as a hobby idea to organize knowledge. The core idea is to own the data and build amazing integrations that make everyday easy. As already mentioned, the homelab today hosts financial data lake, documentation & notetaking software, powerful to-do-listing tools, eBook and audiobook readers, file cloud, photo gallery, smart reminder & notification systems and so on!

## Deployment mechanism

Deployments happen whenever a PR gets merged to the `main` branch. GitHub CI is used for all deployments and the secrets are kept in Bitwarden (non self-hosted). Whenever there's code merged, the CI instance boots up, joins my Tailscale network, picks up the Bitwarden secrets, runs the Ansible playbook and goes away once successful. Needless to say, idempotence is therefore a strict requirement here.

## Backup mechanism

All the application containers are mapped to a persistent storage location in the mounted HDD. And this giant data directory is being backed up to object storage (Backblaze B2 in my case). Encrypted, incremental backups - thanks to Duplicati.

## Evolution of the host machine

1. 1GB DigitalOcean droplet
    - The now-archived [repository](https://github.com/rounakdatta/homeserver.setup) used to deploy applications natively (non-containerized) and given memory was limited, very few applications were deployed.
    - Since DO droplets have dedicated IPv4, exposing services publicly was not at all a concern.
2. Raspberry Pi 4
    - The Raspberry Pi performed really well in the initial 3 months of setting up, until summer heat waves spoiled the party.
    - Pis being single-board computers tend to get very hot when overworking.
    - The Pi (ARM) setup was very efficient on power and had an external USB-connected HDD for storage.
    - The Pi ran DietPi - a stripped down Debian-based operating system. With 8GB of memory, it ran a large number of applications really well, although response times were quite high on average.
3. Dell Latitude E6400
    - Migrating to a x64 (AMD64) old laptop was mostly trivial. The Dell machine runs Ubuntu server.
    - CPU, in comparison to the Pi is way more faster and resulted to slightly better response times.
    - Being a laptop, the machine provides battery backup to some extent and also a screen for urgent debugging.
    - However the laptop being decade-old, it tends to heat up a lot and needs active environmental cooling.
4. ASUS Desktop (gaming PC)
    - The second-hand-purchases gaming desktop sports i5 7th generation and 16GB RAM (early 2018 model).
    - Has powerful motherboard with efficient cooling and power unit.
    - Nextcloud, Photoprism, Duplicati performance has clear visible improvements upon migration to this desktop homelab.

## Future scopes

Oracle Cloud offers high-spec ARM machines at free tier, I'm yet to explore if that offering can be put to good use. With that in mind, I'm also looking into distributed deployments. One of the main challenges in that is exposing a distributed interface for storage (like Ceph, SeaweedFS etc). Another point of future focus would be good metric collection and monitoring setup.

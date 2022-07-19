![homelab.setup-logo](homelab.setup_logo.png)

This repository hosts all the playbooks required to deploy and run my homelab. You have bring your own hardware, Linux operating system and *data* though.

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

Hashicorp Nomad is undoubtedly a very good orchestrator of services and the declarative design of deployments make it even easier to administer. I also have setup a Caddy webserver as an ingress gateway. There's one Cloudflare Tunnels for each application, and that channels the requests to directly hit the Caddy endpoints. A simple diagram to illustrate the lifecycle of requests:

![request-lifecycle](https://i.imgur.com/VgvjzC6.png)

The way the Ansible playbook is structured makes it super-easy to onboard a new application. Look at some of the past pull-requests to understand how it's only about copy-pasting, filling up templates and adding some secrets.

## Philosophy

The project was born as a hobby idea to organize knowledge. The core idea is to own the data and build amazing integrations that make everyday easy. As already mentioned, the homelab today hosts financial data lake, documentation & notetaking software, powerful to-do-listing tools, eBook and audiobook readers, file cloud, photo gallery, smart reminder & notification system and so on!

## Deployment mechanism

Deployments happen whenever a PR gets merged to the `main` branch. GitHub CI is used for all deployments. Whenever there's code merged, the CI instance boots up, joins my Tailscale network, runs the Ansible playbook and goes away once successful. Hence idempotence is a strict requirement here.

## Backup mechanism

All the application containers are mapped to a persistent storage in the mounted HDD. And this giant data directory is being backed up to object storage (Backblaze B2 in my case). Encrypted, incremental backups - thanks to Duplicati.

## History of the host machine

1. 1GB DigitalOcean droplet
2. Raspberry Pi 4
3. Dell Latitude E6400

## Scope of improvements

# Monorepo layout

This fork (jrmatherly/apisix) holds everything needed to build, run and deploy
Apache APISIX as an AI gateway. Upstream is apache/apisix; the APISIX source
tree itself is unchanged in layout.

| Path | What it is | Origin |
|------|------------|--------|
| `apisix/`, `t/`, `conf/`, … | APISIX 3.19.0 source | apache/apisix (this repo) |
| `dashboard/` | Embedded dashboard (Vite/React), served by APISIX at `/ui/` | git subtree of apache/apisix-dashboard |
| `docker-images/` | Official image Dockerfiles (debian, redhat, ubuntu, all-in-one) and example compose stacks for **released** images | git subtree of apache/apisix-docker |
| `docker/` | Upstream apache/apisix's own dev image: builds APISIX **from this source tree** and bakes `dashboard/` into `/ui/` (`make build-on-debian-dev`, CI) | apache/apisix |
| `deploy/docker/` | AI-gateway compose stack built from this tree | this fork |
| `deploy/kubernetes/` | Values and Flux manifests for the published `apisix` Helm chart | this fork |
| `deploy/routes/` | Sample AI routes (Admin API and declarative YAML) | this fork |
| `docs/ai-gateway.md` | AI gateway plugin guide for this fork | this fork |

`docker/debian-dev` and `docker-images/debian-dev` share a name but are not
copies: the first compiles the checked-out source, the second installs
`apisix master` from LuaRocks onto `api7/apisix-runtime:dev`. Use `docker/`
for anything that should reflect local changes.

The Helm chart (apache/apisix-helm-chart) and the ingress controller
(apache/apisix-ingress-controller) are consumed as published artifacts, not
vendored. The forks stay at `~/dev/apisix-helm-chart` and
`~/dev/apisix-ingress-controller` for reference only.

## Syncing subtrees with upstream

History was kept (`git subtree add` without `--squash`), so pulls merge
upstream history into this repo:

```bash
git subtree pull --prefix=dashboard     https://github.com/apache/apisix-dashboard.git master
git subtree pull --prefix=docker-images https://github.com/apache/apisix-docker.git    master
```

To push a subtree change back to a fork for an upstream PR:

```bash
git subtree push --prefix=dashboard https://github.com/jrmatherly/apisix-dashboard.git <branch>
```

Upstream APISIX itself: `git fetch upstream && git merge upstream/master`.

## Building the embedded UI

The dashboard is served from `<repo>/ui`, which is a build output and is
gitignored. In the devcontainer or anywhere with Node 24 and pnpm:

```bash
make ui   # builds dashboard/ and refreshes ui/
make run
```

Docker images build the dashboard themselves (`docker/debian-dev/Dockerfile`),
so `ui/` is only needed for `make run` outside Docker. Upstream pins a
dashboard commit in `.requirements`; this fork dropped that line because the
subtree at `dashboard/` is the pinned source.

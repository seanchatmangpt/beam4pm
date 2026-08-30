# BEAMOps First Principles: Pattern Adoption for beam4pm

This document explains which infrastructure patterns beam4pm adopted from the *BEAMOps*
book's production-environment chapters, which of those patterns were AWS-specific, what
GCP/GitHub equivalent replaced each one and why, and which book patterns were judged not
applicable at all because the underlying problem they solve does not exist under beam4pm's
architecture. It exists so a reviewer can trace any file under `infra/` back to the book
pattern it descends from without re-deriving the translation by hand. Nothing described
here has been applied against a real cloud account or real GitHub org credentials -- see
**Standing** at the end.

## 1. Packer image build: `amazon-ebs` → `googlecompute`

The book builds a custom AMI with `source "amazon-ebs" "base"`, targeting Amazon Linux and
an `ec2-user` default account (`the_production_environment_and_packer/09_extra_mile/packer/
aws-docker.pkr.hcl`). This is fully AWS-specific: `source_ami_filter`, `ami_regions`, and
`ec2-user` have no meaning outside EC2.

beam4pm's `infra/gcp/packer/beam4pm-image.pkr.hcl` replaces the builder with `source
"googlecompute" "beam4pm"` against a `debian-12` base image, `packer` as the SSH user, and
GCE-native fields (`zone`, `machine_type`, `disk_type = "pd-balanced"`, `image_family`).
The provisioning content was translated in step: the book's `setup.sh` runs `dnf update &&
dnf install docker` (Amazon Linux 2023's package manager); beam4pm's inline provisioner runs
`apt-get install docker.io` (Debian's), then installs a systemd unit (`beam4pm.service`)
that runs the pre-pulled product container (`ghcr.io/seanchatmangpt/beam4pm:latest`) on port
8080. This is a straight builder-and-package-manager swap with no change in intent: bake a
Docker host image with the product container preinstalled, boot it under systemd.

The book's other structural idiom -- keeping provisioning logic in a separate `packer/
setup.sh` file, invoked via `provisioner "shell" { script = "setup.sh" }` -- **is now
adopted**. `infra/gcp/packer/setup.sh` is generated from a new
`packer-setup.sh.tmpl` (fully static: apt-get update, install `docker.io`/
`ca-certificates`/`curl`, enable the docker daemon; zero `b4pi:*` fact interpolation, so it
renders byte-identically for any consumer's `b4pi:PackerImage` individual) and uploaded via
its own `provisioner "file"` + `provisioner "shell"` pair in
`infra/gcp/packer/beam4pm-image.pkr.hcl`. The remaining, genuinely fact-driven content (the
systemd unit body, the `docker pull ${var.container_image}` line, the provenance-facts
write) stays inline in the `.pkr.hcl`'s own heredoc, because Packer's `file` provisioner
copies externally-sourced bytes verbatim and never HCL-interpolates `${var.*}` inside them --
that content genuinely cannot move into a static sibling file. The book's `cloud-init
status --wait` race-guard has no GCE equivalent to port: `googlecompute` has no asynchronous
cloud-init step for Packer's shell provisioner to race against, so nothing was lost by its
absence.

The book's `variables.pkr.hcl` (typed variable, no default) plus a separate
`.auto.pkrvars.hcl` (the actual override value, auto-loaded by Packer with no `-var-file`
flag) is a per-environment override idiom beam4pm's `infra/gcp/packer/variables.pkr.hcl`
does not yet mirror -- it bakes explicit placeholder defaults (e.g. `project_id =
"beam4pm-pro-demo"`) directly into each `variable` block instead. This is a legitimate,
currently-non-blocking gap: adding `infra/gcp/packer/.auto.pkrvars.hcl` per environment
would let a real `project_id` be supplied without touching generated files, matching the
book's idiom exactly.

## 2. Deployment/scaling: EC2 Autoscaling Group + Swarm → Cloud Run managed scaling

This is the largest single piece of book infrastructure that was not translated, because it
solves a problem beam4pm's architecture does not have.

The book's `autoscaling_and_optimizing_your_deployment_strategy` chapter builds an entire
self-assembling VM fleet: an `aws_launch_template` + `aws_autoscaling_group` (min/max size,
`termination_policies`), CloudWatch-alarm-driven `aws_autoscaling_policy` resources
(CPU-threshold scale up/down), an Application Load Balancer (`aws_lb` +
`aws_lb_target_group`), and -- the largest piece -- a Docker Swarm self-organization
mechanism where each freshly-launched EC2 instance polls its own instance metadata service,
an SSM Parameter Store token, and EC2 tags to discover and join the swarm
(`modules/cloud/aws/compute/swarm/{autoscaling,main,iam,lb}.tf`, `scripts/launch_node.sh`).
An EventBridge rule reacts to ASG-termination events to demote departed swarm nodes.

None of this is applicable to beam4pm, not as an AWS-vs-GCP translation problem but because
`infra/gcp/cloudrun/main.tf`'s `google_cloud_run_v2_service` makes the entire apparatus
unnecessary by construction:

- **Autoscaling**: `scaling { min_instance_count = var.min_instances; max_instance_count =
  var.max_instances }` (default `0`/`3`) replaces the launch-template + ASG + CloudWatch
  alarm chain. Cloud Run scales on concurrent requests per instance
  (`max_instance_request_concurrency`), not a CPU-percentage threshold, so there is no
  alarm-and-policy pair to configure -- the knob the book tunes doesn't exist here.
- **Fleet coordination**: there are no VMs to coordinate, so the entire Swarm
  self-assembly script, the SSM token exchange, and the EC2-tag-based membership protocol
  have no target. Each Cloud Run revision's instances are opaque and stateless; none of them
  ever "join" anything.
- **Load balancing**: Cloud Run provides an HTTPS endpoint and readiness handling
  (`template.startup_probe` in `main.tf`) as part of the managed service; no separate
  `aws_lb`/target-group/listener trio is needed.
- **Rollback**: the book relies on Docker Swarm's own `deploy.rollback_config` in
  `compose.yaml`. Cloud Run's revision model is itself the rollback mechanism -- traffic is
  re-pointed at a prior revision (`traffic { type =
  "TRAFFIC_TARGET_ALLOCATION_TYPE_LATEST" }`), no Swarm-specific config needed.

Porting the AWS ASG/Swarm apparatus into a GCP shape (e.g. a Managed Instance Group +
`google_compute_autoscaler`) would be a regression for a Cloud-Run-targeted deployment, not
an improvement -- it would reintroduce a fleet-management problem Cloud Run's managed
scaling already eliminates. It remains a legitimate future pattern only if beam4pm ever adds
a non-Cloud-Run GCP compute path, which it does not currently have.

## 3. GitHub-provider Terraform (repo/milestones/labels/issues): investigated, reverted

The book's `use_terraform_to_create_github_issues_and_milestones` chapter manages GitHub org
state -- repository settings, milestones, labels, and issues -- entirely through the
`integrations/github` Terraform provider (`github_repository`,
`github_repository_milestone`, `github_issue_label`, `github_issue`). None of this touches
AWS at all; every resource in this chapter is provider-agnostic to the underlying cloud, and
a real, already-vendored pack for exactly this shape exists:
`vendor/ggen-marketplace/packs/gh-terraform-pack` (v0.2.0), whose own reference bodies are
modeled verbatim on this same book's `~/dev/beamops` example.

This was built for real, not just planned: `ghtf:RepoManagementInstance` individuals were
drafted for beam4pm's own repository/5 milestones/8 labels/10 issues (the milestones/labels/
issues sourced from this repo's real, cited backlog -- gate-closure gaps, the CI KNOWN GAP,
the Cloud Run/Packer apply-proof follow-ups -- not the book's fictional kanban-app
placeholders), `gh-terraform-pack` was wired into `ggen.toml [packs]`, and the result was
rendered for real in an isolated scratch copy of this repo (this repo's own "run it, don't
just describe it" discipline). That render surfaced a load-bearing defect the pack's own
`pack.toml`/`ontology.ttl` prose does not disclose: `gh-terraform-pack` ships its own real,
unscoped `ghtf:RepoManagementInstance` individuals directly in its ontology.ttl -- its
self-referential `seanchatmangpt/ggen` (+ an `org_retail` example) reference/dogfood data --
and every family template SPARQL-selects across the **whole unified graph** with no
per-consumer/per-repo scoping predicate anywhere in the pack. Confirmed consequences:

- **family `"repository"`**: a hard, unconditional `terraform validate` failure -- the
  pack's own example and beam4pm's individual both render as
  `resource "github_repository" "managed"`, a duplicate resource address in the same file.
- **families `"milestones"`/`"labels"`**: not a hard error, but unconditionally polluted
  with the pack's own `seanchatmangpt/ggen` reference data (confirmed: 6 milestones rendered
  where only 5 were beam4pm's; 19 labels where only 8 were).
- Every other family (`branch-protection.tf`, `collaborators.tf`, `environments.tf`,
  `files.tf`, `org-security.tf`, `rulesets.tf`, `secrets.tf`, `teams.tf`, `webhooks.tf`,
  `providers.tf`) also renders unconditionally, entirely from the pack's own bundled data,
  regardless of anything a consumer declares.
- Only family `"issues"` renders clean (the pack ships zero issues examples) -- not enough
  on its own to justify an `infra/terraform/github/` directory otherwise full of a different
  project's Terraform resources sitting under beam4pm's own infra tree.

The wiring was reverted (`ggen.toml`, `ontology.ttl`) rather than shipped broken or
misleading; see the "gh-terraform-pack consumption -- INVESTIGATED AND DECLINED" comment
block in `ontology.ttl` for the full record. This is not this repo's pack to fix (shared
marketplace capital in a vendored submodule, not beam4pm-specific) -- it is a real,
reportable gap in `gh-terraform-pack` itself (missing per-consumer instance-data scoping),
independent of AWS/GCP/GitHub-hosting concerns entirely.

## 4. CI dependency caching: portable as-is

`set_up_integration_pipelines_with_github_actions`'s `actions/cache@v4` pattern (a
`mix`/`_build` cache keyed on `${{ runner.os }}-mix-<elixir>-<erlang>-${{
hashFiles('mix.lock') }}` with a graduated `restore-keys` fallback chain, plus a parallel
Dialyzer PLT cache) is entirely provider-agnostic -- it references BEAM toolchain versions
and lockfile hashes, not cloud infrastructure. `.github/workflows/beam4pm-ci.yml` carries
the same shape today: a `rebar3` dependency cache and a `mix` dependency cache, each keyed
on `${{ runner.os }}-<tool>-<otp>-<rebar3-or-elixir>-${{ hashFiles(...) }}` with a
three-level `restore-keys` fallback, mirroring the book's graduated-key idiom. A Dialyzer
PLT cache is not yet present, since this repo's CI job has no Dialyzer step to cache for.

## 5. CI Docker multi-arch build: not yet adopted

The book's `docker/setup-qemu-action` + `platforms: linux/amd64,linux/arm64` addition, and
its registry-backed `cache-from`/`cache-to: type=registry,ref=ghcr.io/...:cache`, are also
provider-agnostic (QEMU emulation and GHCR are not AWS constructs). `.github/workflows/
beam4pm-container.yml` already uses `docker/setup-buildx-action`, but has no
`setup-qemu-action` and no `platforms:` key -- it builds single-architecture (implicit
`linux/amd64`) -- and its cache backend is `type=gha` rather than the book's
`type=registry`. `type=gha` is a valid, arguably more modern choice for a repo already on
GitHub Actions (it avoids a second registry round-trip), so this is a deliberate difference
in cache backend, not a defect. Multi-arch support itself remains unadopted; it is a
legitimate additive gap if beam4pm ever needs arm64 runners, tracked as a follow-up rather
than folded into the infra-provisioning work that produced this document, since
`beam4pm-container.yml` carries a real `packages: write` scope and pushing an untested
multi-platform change through it is a separate, higher-privilege change.

## 6. CI infra validate (Terraform + Packer): newly adopted

No book chapter's CI workflow validates its own Terraform/Packer configuration in CI --
`.github/workflows/beam4pm-infra-validate.yml` is a new addition, not a ported book pattern,
closing a real gap the CI-caching and multi-arch analysis above surfaced along the way:
nothing in this repo's CI had ever exercised `terraform validate` or `packer validate`
before. It runs on pushes/PRs touching `infra/**`, `ontology.ttl`, or
`vendor/ggen-marketplace/packs/beam4pm-pro-infra-pack/**`, with `permissions: contents:
read` and no other scope. Every step is `terraform init -backend=false` /
`terraform validate` or `packer init` / `packer validate` -- never `apply`, never `build`,
never a real backend or real cloud credential. Its Terraform step loops over
`infra/gcp/cloudrun` (and `infra/terraform/github`, guarded by a directory-existence check
that always skips today, per §3 above) so it degrades gracefully rather than needing another
edit if a GitHub-provider module is ever legitimately added by some other means later.

## Summary table

| Book pattern | AWS-specific? | beam4pm status |
|---|---|---|
| Packer builder (`amazon-ebs`) | Yes | Adopted, translated to `googlecompute` (`infra/gcp/packer/`) |
| Packer setup script content (`dnf`/`ec2-user`) | Yes | Adopted, translated to `apt-get`/Debian |
| Packer script-file separation | No (mechanism) | Adopted (`infra/gcp/packer/setup.sh`, new `packer-setup.sh.tmpl`) |
| Packer `.auto.pkrvars.hcl` override file | No (mechanism) | Not adopted; defaults baked into `variables.pkr.hcl` instead |
| EC2 launch template + ASG + CloudWatch scaling | Yes, fully | Not applicable -- replaced by Cloud Run's managed `scaling{}` block |
| Docker Swarm self-assembly + SSM/EventBridge | Yes, fully | Not applicable -- no VM fleet exists to coordinate |
| Application Load Balancer | Yes, fully | Not applicable -- Cloud Run provides the endpoint natively |
| GitHub-provider Terraform (repo/milestones/labels/issues) | No | Investigated + built + reverted -- real `gh-terraform-pack` scoping defect, see §3 |
| CI dependency caching (`actions/cache`) | No | Adopted (`beam4pm-ci.yml`, rebar3 + mix caches) |
| CI Dialyzer PLT cache | No | Not adopted -- no Dialyzer step exists yet |
| CI Docker multi-arch (QEMU + platforms) | No | Not yet adopted; tracked follow-up |
| CI Terraform/Packer validate workflow | No | Adopted, new (`beam4pm-infra-validate.yml`, not a book pattern) |

## Standing

This document describes pattern lineage, not verified deployment state. Consistent with
this repo's honest-standing convention (see `infra/gcp/packer/README.md` and
`infra/gcp/cloudrun/README.md`):

- **Validated locally only, now also in CI.** Everything currently under `infra/gcp/` has
  been exercised only as far as `packer validate` and `terraform init -backend=false &&
  terraform validate` (`tofu validate` as a second engine for the Terraform module,
  confirmed passing with both engines) -- now also automatically on every push/PR via
  `beam4pm-infra-validate.yml` (§6). No `packer build`, no `terraform plan`, no
  `terraform apply`, and no real GCP credentials have ever touched either directory.
- **No GitHub credentials used or required.** Section 3's GitHub-provider Terraform pattern
  was built and rendered in an isolated scratch copy only, then reverted before landing in
  this repo's real ontology/ggen.toml; nothing described here has created, modified, or read
  real GitHub org/repo/issue state via the `integrations/github` provider.
- **A real deploy or build additionally requires** a real GCP `project_id`, the
  `ghcr.io/seanchatmangpt/beam4pm` container image mirrored into Artifact Registry (Cloud
  Run cannot pull `ghcr.io` directly; GCE image builds do not need this), and IAM/billing
  authority neither this document nor the modules it describes have or claim.
- **Marketplace listing, purchase, and entitlement** for beam4pm_pro remain BLOCKED on
  external authorities (a GCP Marketplace seller/producer account); nothing described here
  changes that standing.

## See Also

- `infra/gcp/packer/README.md` -- generated Packer module reference and its own Standing section
- `infra/gcp/cloudrun/README.md` -- generated Cloud Run module reference and its own Standing section
- `docs/reference/beam4pm_types_reference.md` -- generated record-type reference (unrelated domain, same reference-doc conventions)
- `docs/case-studies/xaas-ocel-compatibility.md` -- this repo's honest-standing case-study format this document also follows

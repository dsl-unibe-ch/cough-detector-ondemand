# Equine Cough Detector — Open OnDemand app

Open OnDemand `batch_connect` app definition for the **Equine Cough Detector**, a tool
that detects cough events in long audio recordings of horses. Maintained by the
[Data Science Lab](https://www.dsl.unibe.ch/), University of Bern.

This repository contains **only the OnDemand app definition** — the YAML/ERB files that
tell OnDemand how to submit the job and how to connect to it. There is nothing to build
and no dependencies to install. The application itself ships as a pre-built Apptainer
image that DSL maintains on `/storage`.

## How a session works

```
User → OnDemand dashboard (HTTPS)
         └─ submits SLURM GPU job on cluster "ubelix"
              └─ template/before.sh.erb   picks a free port, generates a session password
              └─ template/script.sh.erb   apptainer exec … cd_app  (Streamlit on that port)
              └─ template/after.sh        waits for the port to open
         └─ view.html.erb shows the password + a Connect button
User → /node/<host>/<port>/ → Streamlit UI (password-gated)
```

---

## Deployment (UBELIX IT)

1. **Clone into the system apps directory.** The directory name becomes the app's URL
   token, so please keep it `cough_detector`:

   ```bash
   git clone https://github.com/dsl-unibe-ch/cough-detector-ondemand \
       /var/www/ood/apps/sys/cough_detector
   ```

2. **Restrict visibility to the access group.** OnDemand hides system apps whose
   directory the requesting user cannot read, so group ownership is the access control:

   ```bash
   chgrp -R <ACCESS_GROUP> /var/www/ood/apps/sys/cough_detector
   chmod -R o-rwx          /var/www/ood/apps/sys/cough_detector
   ```

   > `<ACCESS_GROUP>` is the ID group created for this app — DSL will supply the exact
   > name alongside this repository.

3. **There is no step 3.** No Python environment, no container build, no service, no
   cron. Updates are `git pull` in the app directory.

### Cluster prerequisites

| Requirement | Why |
|---|---|
| `cluster: "ubelix"` cluster config present | referenced by `form.yml` |
| `Apptainer` module loadable on `gpu` / `gpu-invest` nodes | `script.sh.erb` runs `module load Apptainer` |
| NVIDIA driver + `--nv` passthrough | inference runs on GPU |
| `/storage` mounted on compute nodes | audio input and report output both live there |

The `form.yml` attributes (`auto_accounts`, `partition`, `qos`, `gpu`, `gpu_number`,
`wckey`, `reservation`, `advanced_mode`) follow the existing UBELIX OnDemand
conventions and mirror the DSL `text_lab` app already running on this installation.

---

## DSL-owned artifacts

Everything heavy lives outside this repository, under a path DSL owns and updates.
**IT never builds or replaces these.**

| Path | Contents | Override |
|---|---|---|
| `/storage/research/dsl_shared/solutions/ondemand/cough_detector` | deployment root | `COUGH_DETECTOR_DIR` |
| `…/container/cough_detector.sif` | Apptainer image (~4.7 GB) | `COUGH_DETECTOR_SIF` |
| `…/container/checkpoints/` | `bg_model/` + `cough_model/` weights, bind-mounted read-only at `/models` | `COUGH_MODELS_HOST_DIR` |

The defaults are baked into `template/script.sh.erb`; the environment variables exist so
a developer can point a sandbox copy at a local build without editing tracked files.
DSL rebuilds and replaces the `.sif` in place — no OnDemand change is needed for an
application update.

### Bind mounts

- `--bind /storage:/storage` — users select a working directory anywhere under
  `/storage`; the app reads the recordings there and writes the CSV and PDF reports back
  beside them. Without this bind the workflow cannot complete.
- `--bind <checkpoints>:/models:ro` — the image sets `COUGH_MODELS_DIR=/models` and
  auto-detects `bg_model/` and `cough_model/` inside it.

---

## Security model

Please read this section before changing anything in `template/` or `view.html.erb` —
each point below is the result of a failure we already hit.

**The bound port is reachable by other cluster users.** Streamlit listens on
`0.0.0.0:<port>` on a shared compute node, and the cluster network is not firewalled
between nodes. The port alone is not a secret.

**Therefore every session gets a random password.** `template/before.sh.erb` generates a
16-character alphanumeric password (~95 bits of entropy) and exports it as
`COUGH_APP_TOKEN`. The application refuses to render any page until it is entered, and
compares it in constant time. The password is shown to the user only through the
OnDemand dashboard, which is HTTPS.

**`submit.yml.erb` must keep `conn_params: [password]`.** OnDemand's `TemplateBinding`
exposes only `host` and `port` by default. Without that declaration `view.html.erb`
fails with `undefined local variable or method 'password'` and the session card renders
an error instead of the connect button.

**Traffic uses `/node/` (plain HTTP), and this is deliberate.** A self-signed TLS setup
connecting via `/rnode/` was implemented and then reverted: this OnDemand installation
does not accept self-signed backend certificates, and the result was a proxy error on
every connect. Please do not "fix" `/node/` back to `/rnode/`. If TLS on the
proxy→node hop is required, it needs a certificate this installation actually trusts —
we are happy to work with you on that.

**The password interpolation in `view.html.erb` is safe only because of the charset.**
It is placed inside an inline `onclick` attribute without HTML escaping, which is fine
for `[A-Za-z0-9]`. If the generator in `before.sh.erb` is ever widened to include
punctuation, that interpolation must be escaped first.

---

## Troubleshooting

**"Timed out waiting for server on port …"** — on a cold node the job must read the
~4.7 GB image off GPFS before Streamlit binds. `template/after.sh` allows 300 s. If this
recurs, check GPFS health and the job's `output.log` in the session directory.

**`ERROR: apptainer not found on PATH`** — the `Apptainer` module did not load on the
assigned node. Confirm the module is available on the `gpu` and `gpu-invest` partitions.

**`ERROR: Apptainer image not found` / `Models directory not found`** — the DSL
deployment path is missing or unreadable by the user. Both paths must be readable by
members of the access group; the job runs as the user, not as a service account.

**Job rejected by SLURM** — `A100`, `H100` and `H200` require the
`job_gpu_preemptable` QoS. The form's help text says so, but the combination is easy to
get wrong.

**App does not appear on the dashboard** — the user is not in the access group, or the
app directory is not readable by that group (see Deployment step 2).

---

## Application source

The Streamlit application source and the container build recipe are not public at this
time; the underlying research is unpublished. They are available from DSL on request,
and the deployed image is reproducible by us on demand.

**Support:** support.dsl@unibe.ch

## License

MIT — see [LICENSE](LICENSE). Applies to the OnDemand app definition in this
repository; the application image and model weights are distributed separately and are
not covered by it.

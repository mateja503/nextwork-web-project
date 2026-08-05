# File Guide — What Everything In This Project Does

Personal reference. For each file: what it is, why it exists, and what breaks
without it.

**Project in one sentence:** a Java web app (single JSP page) that gets built by
CodeBuild and deployed to an EC2 instance by CodeDeploy, with CodePipeline
triggering the whole thing on every push to `master`.

---

## Quick map

```
nextwork-web-project/
├── src/main/webapp/
│   ├── index.jsp              ← THE ACTUAL APP
│   └── WEB-INF/web.xml        ← servlet descriptor (required by the WAR spec)
├── pom.xml                    ← how Maven builds it
├── settings.xml               ← where Maven downloads dependencies FROM
├── run-tests.sh               ← tests that run before the build
├── buildspec.yml              ← instructions for CodeBuild  (BUILD phase)
├── appspec.yml                ← instructions for CodeDeploy (DEPLOY phase)
└── scripts/                   ← the scripts appspec.yml calls
    ├── install_dependencies.sh
    ├── start_server.sh
    └── stop_server.sh
```

Rule of thumb for remembering the two YAML files:

- **`buildspec.yml` = how to MAKE the thing.** Read only by CodeBuild.
- **`appspec.yml` = where to PUT the thing.** Read only by CodeDeploy.

They never read each other. The only thing connecting them is the `.war` file
that the first one produces and the second one consumes.

---

## The application

### `src/main/webapp/index.jsp`
The entire web application. A plain HTML page served by Tomcat.

Everything else in this repo exists to get *this file* onto a server
automatically. When you push a change here, that change appears on the live site
a few minutes later with no manual work — that's the point of the project.

> Currently contains a leftover test line (`<p>heeeeeee</p>`) from when you were
> verifying the pipeline worked. Harmless, still deployed.

### `src/main/webapp/WEB-INF/web.xml`
The servlet deployment descriptor. Java's WAR specification requires a
`WEB-INF/web.xml` for the archive to be a valid web application.

Yours is essentially empty — just a display name. That's fine; it's a
placeholder satisfying the spec. If you ever add servlets, URL mappings, or
filters, they get declared here.

**Without it:** Tomcat may refuse to recognise the WAR as a deployable web app.

---

## The build

### `pom.xml`
Maven's project definition. Four things it controls:

| Line | Setting | Why it matters |
|---|---|---|
| 6 | `<packaging>war</packaging>` | Produce a `.war`, not a `.jar`. Tomcat only accepts WARs |
| 11–16 | JUnit 3.8.1 dependency | Declared but **unused** — no Java test files exist. Your real tests are in `run-tests.sh` |
| 19 | `<finalName>nextwork-web-project</finalName>` | **Important.** See below |

**Why `<finalName>` matters:** by default Maven would output
`nextwork-web-project-1.0-SNAPSHOT.war` — with the version number baked into the
filename. But `appspec.yml:4` looks for an exact path. If you bumped the version
from `1.0-SNAPSHOT` to `1.1`, the filename would change, CodeDeploy would look
for a file that no longer exists, and every deploy would break.

`<finalName>` pins the output to a stable `nextwork-web-project.war` regardless
of version.

### `settings.xml`
Tells Maven to download dependencies from **your private CodeArtifact
repository** instead of the public Maven Central.

Three blocks, and you need all three:

- **`<servers>`** — the credentials. Username is literally the string `aws`; the
  password is `${env.CODEARTIFACT_AUTH_TOKEN}`, read from an environment
  variable at build time. **No secret is stored in this file** — it's a
  placeholder that gets filled in from the environment.
- **`<profiles>`** — declares the CodeArtifact repository URL.
- **`<mirrors>`** with `<mirrorOf>*</mirrorOf>` — the important one. The `*`
  means *every* dependency request gets redirected through CodeArtifact, not
  just some. Without this, Maven would still hit Maven Central for anything not
  explicitly listed in the profile.

The three `<id>` values are all `nextwork-nextwork-devops-cicd` — that's not a
coincidence, it's **required**. Maven matches the server credentials to the
repository by ID. If they don't match exactly, Maven finds the repo but doesn't
know which credentials to send, and you get a 401.

> **Why use CodeArtifact at all instead of Maven Central?** So builds don't
> depend on a third party staying online, and so dependencies get cached in your
> own account. If an upstream artifact is removed, your builds keep working.

### `run-tests.sh`
Three checks that run **before** the build:

1. Does `src/` exist?
2. Does `src/main/webapp/index.jsp` exist?
3. A trivial always-passes check.

These are **structural checks, not real unit tests.** They verify the project
layout is intact — they don't test any application behaviour.

**Why they run before `mvn compile`:** they take under a second, a Maven compile
takes much longer. If the structure is broken there's no point paying for the
compile. Any `exit 1` here kills the whole pipeline immediately.

---

## The pipeline configuration

### `buildspec.yml` — read by CodeBuild

Runs in four phases, in this order:

| Phase | What happens | Why |
|---|---|---|
| `install` | Sets runtime to `java: corretto8` | Amazon's build of Java 8 |
| `pre_build` | Gets a CodeArtifact auth token, exports it | Maven can't authenticate without this. **This is the step that needs IAM permissions** |
| `build` | Runs `run-tests.sh`, then `mvn -s settings.xml compile` | Test first, fail fast |
| `post_build` | `mvn -s settings.xml package` | Bundles compiled classes into the `.war` |

**The `-s settings.xml` flag is mandatory.** Without it Maven ignores your
CodeArtifact config entirely and silently falls back to Maven Central.

**The `artifacts:` block at the bottom is easy to overlook but critical.** It
lists what gets passed to the deploy stage:

```yaml
artifacts:
  files:
    - target/nextwork-web-project.war   ← the app
    - appspec.yml                       ← deploy instructions
    - scripts/**/*                      ← the lifecycle scripts
  discard-paths: no
```

CodeDeploy needs all three. If `appspec.yml` or `scripts/` weren't listed here,
the build would succeed and then the deploy would immediately fail with "appspec
file not found" — because the files never left the build stage.

`discard-paths: no` preserves the directory structure. If it were `yes`,
everything would be flattened into one folder and `scripts/start_server.sh`
would become just `start_server.sh` — breaking every path in `appspec.yml`.

### `appspec.yml` — read by CodeDeploy

Two sections.

**`files:`** — copy `target/nextwork-web-project.war` to
`/usr/share/tomcat/webapps/`. Tomcat watches that directory and auto-expands any
WAR dropped into it. That's what makes the app go live.

**`hooks:`** — scripts to run at specific points. All run as `root` with a
300-second timeout.

---

## The deployment lifecycle

This is the part worth internalising. CodeDeploy runs these hooks **in this
order** — note that it is *not* the order they appear in `appspec.yml`:

```
1. ApplicationStop    → scripts/stop_server.sh          Stop services first
2. BeforeInstall      → scripts/install_dependencies.sh Make sure Tomcat/httpd exist
3. Install            → (CodeDeploy copies the WAR)     Built-in, no script
4. ApplicationStart   → scripts/start_server.sh         Bring services back up
```

Services must stop before the WAR is replaced — you can't reliably overwrite a
file Tomcat currently has open.

### `scripts/stop_server.sh`
Stops httpd and Tomcat. Uses `pgrep` to check each is actually running before
trying to stop it — stopping an already-stopped service returns an error, which
would fail the hook and fail the whole deployment.

> ⚠️ **The gotcha worth remembering:** `ApplicationStop` runs from the
> **previously deployed revision**, not the new one. So if you ever push a broken
> `stop_server.sh`, it gets "stuck" — every subsequent deployment keeps running
> the broken copy already on the instance, and pushing a fix doesn't help,
> because the fix can't be installed until the broken stop script succeeds. You
> have to fix it manually on the instance or force a fresh deployment ignoring
> the stop hook.

### `scripts/install_dependencies.sh`
Two jobs:

1. `yum install tomcat httpd` — the servlet container and the web server.
2. Writes `/etc/httpd/conf.d/tomcat_manager.conf` — the reverse proxy config.

**Why the reverse proxy exists:** Tomcat serves the app at
`localhost:8080/nextwork-web-project/` — an awkward URL on a non-standard port.
httpd listens on port 80 (the default for `http://`) and forwards requests to
Tomcat, so visitors reach the app at the domain root. It also means Tomcat never
needs to be exposed to the internet directly.

The two directives doing the work:
- `ProxyPass /` → forwards incoming requests to Tomcat
- `ProxyPassReverse /` → rewrites Tomcat's response headers so redirects point
  back at the public address rather than `localhost:8080`

> This script runs on **every** deployment, reinstalling packages that are
> already there. Harmless but wasteful — it really belongs in a one-time
> instance bootstrap or a custom AMI.

### `scripts/start_server.sh`
Starts both services and runs `systemctl enable` on each, so they come back
automatically if the instance reboots. `start` alone would not survive a restart.

---

## What happens on a `git push` — end to end

```
you push to master
  → CodePipeline detects it (Source stage)
  → CodeBuild starts (buildspec.yml)
      → gets CodeArtifact token          [needs IAM permissions]
      → runs run-tests.sh                [fails here = pipeline stops]
      → mvn compile
      → mvn package → nextwork-web-project.war
      → bundles war + appspec.yml + scripts/ as the output artifact
  → CodeDeploy starts (appspec.yml)
      → stop_server.sh
      → install_dependencies.sh
      → copies war to /usr/share/tomcat/webapps/
      → start_server.sh
  → Tomcat auto-expands the war
  → change is live
```

If **any** step exits non-zero, the deployment fails and CodeDeploy rolls back to
the last working revision. You verified this deliberately on 29 Jul 2026 by
breaking `stop_server.sh` on purpose (commit `8b10901`) and confirming the
rollback fired, then reverting it (`21f1a5e`).

---

## Is everything accounted for?

Yes — every file in the repo has a purpose, and every file referenced by config
actually exists:

| Referenced by | Path | Present? |
|---|---|---|
| `appspec.yml:7` | `scripts/install_dependencies.sh` | ✅ |
| `appspec.yml:11` | `scripts/start_server.sh` | ✅ |
| `appspec.yml:15` | `scripts/stop_server.sh` | ✅ |
| `buildspec.yml:17` | `run-tests.sh` | ✅ |
| `buildspec.yml:21` | `settings.xml` | ✅ |
| `run-tests.sh:13` | `src/main/webapp/index.jsp` | ✅ |
| `appspec.yml:4` | `target/nextwork-web-project.war` | ⚙️ generated at build time — correct that it's not in the repo |

Nothing is missing and nothing is orphaned.

---

## Things to be aware of

- **JUnit 3.8.1 is declared but unused.** No Java test files exist. JUnit 3 is
  also long obsolete — if you ever write real tests, go to JUnit 5.
- **Your AWS account ID (`444660173389`) is committed** in `buildspec.yml:10` and
  `settings.xml:20,30`. Not a secret like an access key, but normally kept out of
  public repos. Moving it to a CodeBuild environment variable is cleaner.
- **The scripts assume Amazon Linux** (`yum`). On Ubuntu/Debian they'd fail —
  you'd need `apt-get` and a different Tomcat webapps path.
- **Single instance, no load balancer.** Every deploy causes brief downtime while
  Tomcat restarts.
- **No HTTPS.** httpd serves plain HTTP on port 80.

---

## Region and account

Everything lives in **`eu-central-1`**, account **`444660173389`**. The
CodeArtifact domain is `nextwork`, repository `nextwork-devops-cicd`.

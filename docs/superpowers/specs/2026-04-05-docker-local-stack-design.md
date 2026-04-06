# Docker Image and Local Compose Stack Design

## Summary

This spec defines a Docker-based local stack for the main application that supports both:

- local development with source-code bind mounts and fast iteration
- regular local use on a single machine without requiring a cloud-style deployment model

The design uses one multi-stage `Dockerfile` and a Docker Compose stack with:

- a default `web + db` path
- optional `worker + rabbitmq` services for asynchronous image processing

The stack is explicitly optimized for one-machine use with a host bind mount for the real image library. Camera USB access remains outside Docker for the first version.

## Goals

- Build one reusable application image for local development and local deployment.
- Make `docker compose up --build` sufficient for the default browsing stack.
- Keep the default stack lean by excluding Celery and RabbitMQ unless requested.
- Support the real host image library through bind mounts.
- Reuse the same image for Django web, Celery worker, and one-off management commands.
- Keep the setup portable across Windows, macOS, and Linux Docker workflows.

## Non-Goals

- USB camera passthrough from containers
- multi-host or cloud deployment
- production TLS, reverse proxying, or load balancing
- Kubernetes or orchestration beyond Docker Compose
- adding Memcached to the stack before the application actually uses it

## Current Repository Constraints

The current repository already implies the runtime shape:

- Django 6 is the main web application framework.
- PostgreSQL is the configured database backend.
- Celery is used for asynchronous image and thumbnail processing.
- RabbitMQ is the documented Celery broker.
- `exiftool` is required for image-processing commands.
- thumbnail caching is filesystem-based, not Memcached-based
- camera operations use `pyusb` and `libusb`, but USB access is not portable enough to make part of the first Docker target

Memcached is mentioned in setup documentation but is not configured in Django settings and is not used by current application code. It is excluded from this design.

Cross-platform support introduces additional constraints:

- host paths must not be hard-coded in the Compose file
- the default workflow must work with Docker Desktop on Windows and macOS as well as Docker Engine on Linux
- image-library mounting must be documented in a way that is compatible with Windows drive-letter paths and Unix-style paths
- USB camera passthrough remains out of scope partly because it is especially inconsistent across host operating systems

## Proposed Artifacts

The implementation should introduce:

- one multi-stage `Dockerfile`
- one primary `compose.yaml`
- either Compose profiles in the primary file or a small override file for async services
- one lightweight entrypoint script for startup coordination
- one Compose environment file such as `.env`
- documentation covering common commands and mount expectations
- documentation covering Windows, macOS, and Linux path examples where the user must supply host-specific values

## Architecture

### Services

Default stack:

- `db`: PostgreSQL with a named volume for persistent database storage
- `web`: Django application container

Optional async stack:

- `rabbitmq`: message broker for Celery
- `worker`: Celery worker built from the same application image as `web`

### Default Behavior

The default user path should be:

```bash
docker compose up --build
```

That command should bring up:

- PostgreSQL
- the Django web application on port `8000`

It should not require RabbitMQ or Celery for basic browsing, filtering, ratings, recipe graphs, or synchronous imports.

### Optional Async Behavior

Async processing should be opt-in. The user should explicitly enable it when they want background image processing or bulk thumbnail generation through Celery.

Preferred command shape:

```bash
docker compose --profile async up --build
```

If profiles prove awkward during implementation, a small override file is acceptable:

```bash
docker compose -f compose.yaml -f compose.async.yaml up --build
```

The implementation should prefer profiles unless the repo’s actual compose ergonomics strongly favor an override file.

## Docker Image Design

### Multi-Stage Strategy

The `Dockerfile` should use a multi-stage layout:

- `base`: shared Python and OS-level runtime prerequisites
- `dev`: development-oriented target used by Compose for local development and local use
- `runtime`: slimmer target for a more fixed local deployment path

This keeps dependency installation centralized while allowing a development-friendly target and a smaller stable target from the same file.

The Dockerfile itself should remain host-agnostic. Cross-platform handling belongs in Compose configuration and documentation, not in OS-specific image variants.

### Base Image

Use Python 3.11 slim as the base, matching the repository requirement.

The base image should install only the OS packages needed to run the application and install Python dependencies. Expected packages include:

- `exiftool`
- `libusb` runtime package
- packages required to support Python dependency installation if needed by the chosen image variant

Avoid pulling in unrelated system services. PostgreSQL and RabbitMQ run as separate containers, not inside the application image.

### Development Target

The `dev` target should be optimized for:

- bind-mounted source code
- interactive `manage.py` use
- local test and debugging workflows
- running Django with `runserver`

The Compose `web` service should use this target by default for the initial implementation because the primary goal is local development plus local single-machine usage.

### Runtime Target

The `runtime` target should:

- install the same Python dependencies
- copy application code into the image
- omit development-only conveniences where practical

This target allows a more stable local deployment mode later without maintaining a second Dockerfile.

## Entrypoint and Startup Behavior

The application image should include a small entrypoint script responsible for predictable startup coordination.

Responsibilities:

- wait for PostgreSQL to accept connections
- optionally run database migrations before starting the main process
- exec the requested container command cleanly

The startup behavior should favor practicality for one-machine use. Running migrations automatically on `web` startup is acceptable for this repo because the target is local development and local personal deployment rather than a hardened multi-instance production system.

The entrypoint must stay minimal. It should not try to manage RabbitMQ, perform application setup unrelated to startup, or hide failures behind broad retry loops.

The entrypoint must also avoid shell assumptions that are brittle across host platforms. Container startup should depend only on the Linux userspace inside the image, not on host-specific shell behavior.

## Compose Design

### Database Service

The `db` service should:

- use an official PostgreSQL image
- expose a named volume for persistent data
- set database name, user, and password via environment variables
- publish a health check or equivalent readiness signal if practical

It does not need to expose the PostgreSQL port to the host by default unless host-side tools require it. Internal Compose networking is sufficient for normal operation.

### Web Service

The `web` service should:

- build from the application `Dockerfile`
- use the `dev` target initially
- bind-mount the repository for live code editing
- bind-mount the host image library into a stable in-container path
- expose `8000:8000`
- depend on `db`
- run the Django development server bound to `0.0.0.0:8000`

The host image-library mount should be explicit and user-configurable. A stable internal path such as `/data/images` is preferred so container-side settings and documentation do not depend on the user’s host directory layout.

The Compose definition should avoid embedding developer-specific absolute host paths. The host path should be provided through an environment variable or equivalent Compose substitution so the same file works on:

- Windows paths such as `C:\Users\arthur\Pictures\Fujifilm`
- macOS paths such as `/Users/arthur/Pictures/Fujifilm`
- Linux paths such as `/home/arthur/Pictures/Fujifilm`

### Worker Service

The optional `worker` service should:

- reuse the same application image and build context
- share the same source and image-library mounts as `web`
- depend on `db` and `rabbitmq`
- run `celery -A src.config worker --loglevel=info --concurrency=8`

Using the same image is important to avoid configuration drift between web and worker execution environments.

### RabbitMQ Service

The optional `rabbitmq` service should:

- use an official RabbitMQ image
- be included only when async mode is enabled
- remain minimally configured unless real application needs require customization

No advanced broker topology or management UI is required in the first iteration.

## Configuration Model

### Settings Strategy

The application currently expects `src/config/settings.py`. Docker support should not replace that module import model.

Instead, the settings implementation should be adjusted, if necessary, to read key values from environment variables with sensible local defaults.

This should cover:

- PostgreSQL database host, port, name, user, and password
- Celery broker URL
- Celery result backend if still required
- any container-specific filesystem paths that should not be hard-coded for host execution

### Environment Sources

Container configuration should come from:

- Compose `environment:` blocks for the most important runtime values
- a standard Compose env file named `.env` for easier local customization

The implementation should avoid forcing users to manually rewrite `settings.py` for Docker use.

For cross-platform compatibility, the implementation should prefer environment variables for host-specific mount inputs, for example an image-library source path provided by the user in an env file that Compose reads.

### Filesystem Paths

The design should make the container filesystem model explicit:

- application source: bind-mounted repo path
- image library: host bind mount at a fixed internal path, such as `/data/images`
- thumbnail cache: either a named volume or a bind-mounted repo-local directory
- logs: preferably a named volume or repo-local bind mount, depending on how visible the logs should be during development

The internal paths should be stable and documented so management commands and troubleshooting instructions are predictable.

Cross-platform rule: internal container paths should always be Linux-style fixed paths, while external host paths must remain configurable. This avoids leaking Windows path syntax into application settings or management command examples.

## Image Library Handling

The host image library is central to this repository’s real use case, so the stack should not try to import or copy the photo library into Docker-managed storage.

The correct default is a host bind mount. This allows:

- reuse of the user’s existing photo directory
- no duplication of large JPEG libraries
- easy invocation of sync or async image-processing commands against real data

The application should refer to the mounted container path, not the host path, when commands run inside containers.

Documentation must show how the host path is supplied on each supported platform, but once mounted, all in-container commands should use the same internal path regardless of host OS.

## Data Flow

### Default Path

1. User starts `db` and `web`.
2. `web` waits for PostgreSQL, applies migrations if configured to do so, and starts Django.
3. User opens the app in a browser on `http://localhost:8000`.
4. User runs management commands in the `web` container for synchronous imports or other one-off tasks.

### Async Path

1. User enables async services.
2. `rabbitmq` starts.
3. `worker` starts from the same application image and consumes from the configured Celery queue.
4. The web app enqueues image-processing or thumbnail-generation tasks.
5. The worker reads the same database and mounted image library as `web`.

The shared mounts and shared image are what keep these flows coherent.

## Error Handling and Operational Expectations

The Docker setup should make the following failure modes straightforward to diagnose:

- database unavailable
- bad database credentials
- missing image-library mount
- invalid host path syntax in Compose configuration
- Docker Desktop file-sharing or filesystem permission issues on Windows or macOS
- missing `exiftool`
- worker started without RabbitMQ

Expected handling:

- fail fast on startup when required dependencies are unavailable
- emit readable container logs
- avoid silent fallbacks that mask configuration problems

The first Docker version does not need advanced observability. Clear container logs are enough.

## Testing Strategy

The Docker work should be verified at three levels.

### Build Verification

- build the `dev` target successfully
- build the `runtime` target successfully

### Stack Verification

- `docker compose up --build` starts `db` and `web`
- Django is reachable on port `8000`
- migrations apply successfully
- the application can connect to PostgreSQL

### Async Verification

- async services start only when explicitly enabled
- `worker` connects to RabbitMQ and PostgreSQL
- a representative Celery task can be enqueued and consumed

### Filesystem Verification

- host image-library bind mount is visible in the container
- thumbnail cache is written to the expected location

### Cross-Platform Verification

- the documented host-path configuration works on Windows
- the documented host-path configuration works on macOS
- the documented host-path configuration works on Linux
- all container-side commands use the same internal image-library path on every host OS

## Explicit Decisions

- Use one multi-stage `Dockerfile`, not separate Dockerfiles.
- Optimize the initial Compose path for local development and local single-machine use.
- Default stack is `web + db`.
- Async stack is optional.
- Use a host bind mount for the real image library.
- Keep host-specific path syntax outside the application settings and inside user-supplied Compose/env configuration.
- Exclude Memcached from the first Docker stack.
- Keep USB camera access outside Docker for the first version.
- Prefer Compose profiles for async services, but allow an override file if implementation ergonomics are clearly better.
- Treat Windows, macOS, and Linux as first-class supported local host platforms.

## Open Questions Resolved By This Spec

- Should async processing be on by default? No.
- Should Memcached be containerized? No.
- Should camera USB support be included? No.
- Should the image library live in Docker-managed storage? No.
- Should there be one Dockerfile or several? One multi-stage Dockerfile.

## Implementation Outline

The implementation phase should produce:

1. `Dockerfile`
2. `compose.yaml`
3. optional async profile or override definition
4. entrypoint script
5. settings updates for environment-driven configuration where needed
6. documentation for common Docker workflows

The implementation plan should stay focused on those artifacts and avoid unrelated refactoring.

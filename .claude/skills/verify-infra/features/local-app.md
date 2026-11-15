# Local app + postgres stack

The default compose services: `postgres:17-alpine` standing in for RDS and the app container (placeholder `nginxinc/nginx-unprivileged`) standing in for EC2.

## Sub-features

- `app-http` app serves HTTP 200 on the host port.
- `app-env` app has `DATABASE_URL` pointing at `postgres:5432/app`, `AWS_ENDPOINT_URL=http://aws:4566`, `AWS_REGION`.
- `db-ready` postgres 17 accepts queries and writes as user `app`.
- `app-hardening` app runs `read_only` with `no-new-privileges`.

## How to get to it (user POV)

- `cp local/.env.example local/.env && make local-up`, then `http://localhost:8080`.

## Driving it with verify.sh

Preconditions: `$S launch` done, `$S doctor` green.

- **Run.** `$S drive local-app`.
- **Proof.** `evidence/local-app/app-response.txt` starts `HTTP/1.1 200 OK`; `app-env.txt` shows the three variables (password masked); `db-read.txt` is `17xxxx|<n>` (server version 17, probe rows >= 1).
- **Ad hoc.** `curl -i http://127.0.0.1:18080/`, `docker inspect verify-infra-app-1 --format '{{.HostConfig.ReadonlyRootfs}} {{.HostConfig.SecurityOpt}}'`.

## Gotchas

- The app is a placeholder nginx; it does not actually read `DATABASE_URL`. The DB check is made from the postgres container, not through the app. When the fullstack team swaps `APP_IMAGE`, replace the HTTP check with a real endpoint that touches the DB.
- The verify run uses ports 18080/15432, not the README's 8080/5432.
- `verify_probe` table is created in the verify DB; it is destroyed with the volume on cleanup.

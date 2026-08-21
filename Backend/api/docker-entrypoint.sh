#!/bin/sh
# Runs as root inside the dev container.
#
# Named volumes (node_modules, .wrangler, .docker-home) are created by Docker
# with root ownership by default — the unprivileged container user can't write
# to them. We detect the host project's UID/GID from the bind-mounted /app
# directory and chown the mount points before exec-ing the real command as
# that user via su-exec.
set -e

TARGET_UID=$(stat -c '%u' /app)
TARGET_GID=$(stat -c '%g' /app)

# Only chown the mount points themselves — not -R; the directories start empty
# and recursive chown on each restart would be slow once node_modules fills up.
for d in /app/node_modules /app/.wrangler /app/.docker-home; do
  [ -d "$d" ] && chown "$TARGET_UID:$TARGET_GID" "$d" || true
done

exec gosu "$TARGET_UID:$TARGET_GID" "$@"

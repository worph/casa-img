#!/bin/sh

# Get UID/GID from environment variables (default to 1000 if not set)
PUID=${PUID:-1000}
PGID=${PGID:-1000}

# Get Docker group ID from the docker socket file
DOCKER_GID=$(stat -c '%g' /var/run/docker.sock 2>/dev/null || echo "999")
ls -al /var/run/docker.sock

# Ensure group with PGID exists
if ! getent group "$PGID" >/dev/null; then
  groupadd -g "$PGID" casaos
fi

# Ensure user with PUID exists
if ! getent passwd "$PUID" >/dev/null; then
  useradd -u "$PUID" -g "$PGID" -M -s /sbin/nologin casaos
fi

# Create necessary directories with proper ownership
mkdir -p /DATA/AppData/casaos/apps
mkdir -p /c/DATA/ # For compatibility with windows host
mkdir -p /var/log/casaos
mkdir -p /var/run/casaos

# Set ownership of directories that will be used by casaos processes
chown -R "$PUID:$PGID" /DATA/
chown -R "$PUID:$PGID" /c/DATA/
chown -R "$PUID:$PGID" /var/log/casaos
chown -R "$PUID:$PGID" /var/run/casaos

# Create log files with proper ownership
touch /var/log/casaos-gateway.log
touch /var/log/casaos-app-management.log
touch /var/log/casaos-user-service.log
touch /var/log/casaos-mesage-bus.log
touch /var/log/casaos-local-storage.log
touch /var/log/casaos-main.log

chown "$PUID:$PGID" /var/log/casaos-*.log

echo "Starting CasaOS services as UID:GID $PUID:$PGID..."
echo "Docker group ID: $DOCKER_GID"

# Start the Gateway service
gosu "$PUID:$PGID" /usr/local/bin/casaos-gateway > /var/log/casaos-gateway.log 2>&1 &

# Wait for the Gateway service to start
while [ ! -f /var/run/casaos/management.url ]; do
  echo "Waiting for the Gateway service to start..."
  sleep 1
done
while [ ! -f /var/run/casaos/static.url ]; do
  echo "Waiting for the Gateway service to start..."
  sleep 1
done

# Start the MessageBus service
gosu "$PUID:$PGID" /usr/local/bin/casaos-message-bus > /var/log/casaos-message-bus.log 2>&1 &

# Wait for the MessageBus service to start
while [ ! -f /var/run/casaos/message-bus.url ]; do
  echo "Waiting for the MessageBus service to start..."
  sleep 1
done

# Start the Main service
gosu "$PUID:$PGID" /usr/local/bin/casaos-main > /var/log/casaos-main.log 2>&1 &

# Wait for the Main service to start
while [ ! -f /var/run/casaos/casaos.url ]; do
  echo "Waiting for the Main service to start..."
  sleep 1
done

# Start the LocalStorage service
gosu "$PUID:$PGID" /usr/local/bin/casaos-local-storage > /var/log/casaos-local-storage.log 2>&1 &

# Wait for /var/run/casaos/routes.json to be created and contains local_storage
while [ ! -f /var/run/casaos/routes.json ] || ! grep -q "local_storage" /var/run/casaos/routes.json; do
    echo "Waiting for /var/run/casaos/routes.json to be created and contains local_storage..."
    sleep 1
done

# Start the AppManagement service with dynamic Docker group ID
gosu "$PUID:$DOCKER_GID" /usr/local/bin/casaos-app-management > /var/log/casaos-app-management.log 2>&1 &

# Start the UserService service
gosu "$PUID:$PGID" /usr/local/bin/casaos-user-service > /var/log/casaos-user-service.log 2>&1 &

# Run the register UI events script
chown -R "$PUID:$PGID" /usr/local/bin/register-ui-events.sh
gosu "$PUID:$PGID" /usr/local/bin/register-ui-events.sh

echo "All CasaOS services started successfully!"

# Tail the log files to keep the container running and to display the logs in stdout
tail -f \
/var/log/casaos-gateway.log \
/var/log/casaos-app-management.log \
/var/log/casaos-user-service.log \
/var/log/casaos-message-bus.log \
/var/log/casaos-local-storage.log \
/var/log/casaos-main.log
# Use the official n8n Docker image as the base
FROM n8nio/n8n:latest

# n8n runs as the "node" user, so switch to root to change permissions
USER root

# The /home/node/.n8n directory is used by n8n to store data.
# The "node" user needs to have ownership of it.
# This is important for environments like Google Cloud Run where the filesystem can be read-only.
RUN chown -R node /home/node/.n8n

# Switch back to the non-root "node" user
USER node

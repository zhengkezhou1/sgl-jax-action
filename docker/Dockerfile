FROM mirror.gcr.io/library/python:3.12-slim

RUN apt-get update && apt-get install -y \
    openssh-server \
    git \
    curl \
    && rm -rf /var/lib/apt/lists/*

RUN sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config \
    && sed -i 's/#PubkeyAuthentication yes/PubkeyAuthentication yes/' /etc/ssh/sshd_config \
    && sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config

RUN echo '#!/bin/bash\n\
set -e\n\
\n\
echo "[INFO] Starting SSH setup..."\n\
\n\
# Ensure .ssh directory exists with correct permissions\n\
mkdir -p /root/.ssh\n\
chmod 700 /root/.ssh\n\
\n\
# Check for SSH public key file\n\
KEY_SRC="/tmp/ssh-keys/authorized_keys"\n\
[ ! -f "$KEY_SRC" ] && KEY_SRC="/tmp/sky_ssh_key"\n\
\n\
if [ -f "$KEY_SRC" ]; then\n\
    echo "[INFO] Found SSH key at: $KEY_SRC"\n\
    cp "$KEY_SRC" /root/.ssh/authorized_keys\n\
    chmod 600 /root/.ssh/authorized_keys\n\
    chown root:root /root/.ssh/authorized_keys\n\
    echo "[INFO] SSH key configured successfully"\n\
else\n\
    echo "[WARN] No SSH key found at $KEY_SRC"\n\
    echo "[WARN] SSH authentication may not work"\n\
fi\n\
\n\
# Start SSH daemon in background\n\
echo "[INFO] Starting SSH daemon..."\n\
/usr/sbin/sshd -D &\n\
\n\
echo "[INFO] Container ready"\n\
exec "$@"' > /entrypoint.sh && chmod +x /entrypoint.sh

ENV JAX_COMPILATION_CACHE_DIR=/tmp/jit_cache
ENV PYTHONUNBUFFERED=1

WORKDIR /workplace/sglang-jax
EXPOSE 22

ENTRYPOINT ["/entrypoint.sh"]
CMD ["/bin/bash"]
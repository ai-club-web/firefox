FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    dbus-x11 \
    firefox-esr \
    libegl1 \
    libpci3 \
    novnc \
    openbox \
    python3-xdg \
    tor \
    websockify \
    x11vnc \
    xvfb \
    && rm -rf /var/lib/apt/lists/*

# Xvfb expects this socket directory to exist and be root-owned with sticky bit.
RUN mkdir -p /tmp/.X11-unix && chmod 1777 /tmp/.X11-unix

RUN useradd -u 10001 -m -s /bin/bash kioskuser \
    && mkdir -p /usr/share/firefox-esr/distribution /usr/lib/firefox-esr/distribution \
    && cp /usr/share/novnc/vnc.html /usr/share/novnc/index.html \
    && sed -i "s/UI.initSetting('resize', 'off');/UI.initSetting('resize', 'scale');/g" /usr/share/novnc/app/ui.js \
    && if [ -f /etc/xdg/openbox/menu.xml ] && [ ! -f /var/lib/openbox/debian-menu.xml ]; then \
         mkdir -p /var/lib/openbox; \
         ln -s /etc/xdg/openbox/menu.xml /var/lib/openbox/debian-menu.xml; \
       fi

COPY policies.json /usr/share/firefox-esr/distribution/policies.json
COPY policies.json /usr/lib/firefox-esr/distribution/policies.json
COPY --chown=10001:10001 entrypoint.sh /home/kioskuser/entrypoint.sh

RUN chmod +x /home/kioskuser/entrypoint.sh

ENV HOME=/home/kioskuser
WORKDIR /home/kioskuser

ENV DISPLAY=:99 \
    VNC_PASSWORD=securepass \
    APP_STATE_DIR=/tmp/kioskuser \
    ENABLE_TOR=true \
    NOVNC_BIND=0.0.0.0 \
    NOVNC_PORT=8080 \
    SCREEN_WIDTH=1368 \
    SCREEN_HEIGHT=768 \
    SCREEN_DEPTH=16 \
    FIREFOX_DISABLE_SANDBOX=true \
    TOR_SOCKS_PORT=9050 \
    TOR_MAX_CIRCUIT_DIRTINESS=60 \
    TOR_NEW_CIRCUIT_PERIOD=30 \
    TOR_BOOTSTRAP_TIMEOUT=90

EXPOSE 8080

ENTRYPOINT ["/home/kioskuser/entrypoint.sh"]

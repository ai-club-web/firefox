FROM ubuntu:20.04

# Install necessary packages
RUN apt-get update && apt-get install -y \
    tor \
    firefox \
    xvfb \
    x11vnc \
    openbox \
    nginx \
    supervisor \
    wget \
    git \
    && rm -rf /var/lib/apt/lists/*

# Install noVNC
RUN git clone https://github.com/novnc/noVNC.git /opt/noVNC && \
    cd /opt/noVNC && git checkout v1.3.0 && \
    ./utils/novnc_proxy --help > /dev/null 2>&1 || true

# Create directory for Tor
RUN mkdir -p /var/lib/tor

# Copy configuration files
COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf
COPY torrc /etc/tor/torrc
COPY firefox-prefs.js /usr/lib/firefox/browser/defaults/preferences/
COPY openbox-autostart /etc/xdg/openbox/autostart
COPY nginx.conf /etc/nginx/sites-available/default

# Expose the port that nginx will listen on (provided by Choreo via PORT)
# We'll set the default to 8080 in nginx.conf but allow override via env
ENV PORT=8080

# Set environment variables for display
ENV DISPLAY=:99

# Start supervisord
CMD ["/usr/bin/supervisord", "-c", "/etc/supervisor/conf.d/supervisord.conf"]

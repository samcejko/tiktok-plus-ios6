# Tikie helper for the Raspberry Pi. yt-dlp does the TikTok extraction; everything else is Python stdlib.
FROM python:3.12-slim

RUN pip install --no-cache-dir -U yt-dlp

COPY tikie_server.py /app/tikie_server.py
WORKDIR /app

ENV TIKIE_PORT=8730
EXPOSE 8730

# yt-dlp is the part that ages; rebuild (or `pip install -U yt-dlp` in the container) when TikTok changes.
CMD ["python", "/app/tikie_server.py"]

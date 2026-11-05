FROM python:3.11-slim

RUN apt-get update && apt-get install -y --no-install-recommends curl ca-certificates && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY config.json crous_watcher.py crous_state.json ./

ENV PORT=8080
EXPOSE 8080

CMD ["python3", "crous_watcher.py"]


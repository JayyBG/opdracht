FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

# Draai niet als root.
RUN useradd --uid 1000 --create-home app \
    && mkdir -p /app/logs \
    && chown app:app /app/logs
USER app

EXPOSE 5000
CMD ["gunicorn", "--config", "gunicorn.conf.py", "app:app"]

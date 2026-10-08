# Taiga Protected 6.10.1
FROM python:3.11-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app

COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

EXPOSE 8003

CMD ["gunicorn", "--workers", "2", "--timeout", "60", "--access-logfile", "-", "--bind", "0.0.0.0:8003", "server:app"]

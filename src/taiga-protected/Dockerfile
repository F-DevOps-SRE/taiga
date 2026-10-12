# Taiga Protected 6.10.1
FROM python:3.14-alpine

ENV PYTHONDONTWRITEBYTECODE=1     PYTHONUNBUFFERED=1     PIP_DISABLE_PIP_VERSION_CHECK=1

WORKDIR /app

# Parches de seguridad del sistema base publicados después de la imagen oficial.
RUN apk upgrade --no-cache

# pip no se usa en runtime: se desinstala para no arrastrar las vulnerabilidades
# de sus dependencias empaquetadas (si hace falta: `python -m ensurepip`).
COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt     && pip uninstall -y pip

COPY . .

EXPOSE 8003

CMD ["gunicorn", "--workers", "2", "--timeout", "60", "--access-logfile", "-", "--bind", "0.0.0.0:8003", "server:app"]

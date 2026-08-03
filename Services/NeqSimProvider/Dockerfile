FROM eclipse-temurin:21.0.8_9-jre

ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1
ENV PHASEXPERT_NEQSIM_SERVICE_VERSION=0.1.0
ENV PHASEXPERT_NEQSIM_SOURCE_COMMIT=3af7b560525b57f2d3da2c803a08e2b41a8d7f5a

WORKDIR /app

RUN apt-get update \
    && apt-get install -y --no-install-recommends python3 python3-pip python3-venv \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN python3 -m venv /opt/neqsim-provider \
    && /opt/neqsim-provider/bin/pip install --no-cache-dir -r requirements.txt

COPY src ./src

USER 1001
EXPOSE 8080

CMD ["/opt/neqsim-provider/bin/uvicorn", "neqsim_provider.main:app", "--host", "0.0.0.0", "--port", "8080", "--app-dir", "src"]

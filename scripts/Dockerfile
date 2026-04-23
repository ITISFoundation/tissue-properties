FROM python:3.12-slim

WORKDIR /work

RUN pip install --no-cache-dir --disable-pip-version-check \
    numpy==2.1.3 \
    pandas==2.2.3 \
    typer==0.15.1 \
    "ruamel.yaml==0.18.6"

COPY tissues_db.py /usr/local/bin/tissues-db
RUN chmod +x /usr/local/bin/tissues-db

ENTRYPOINT ["tissues-db"]

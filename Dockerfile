FROM postgres:latest

RUN apt-get update && apt-get install -y \
    postgresql-server-dev-all \
    build-essential \
    git \
    pgxnclient \
    postgresql-contrib \
    postgresql-${PG_MAJOR}-cron \
    postgresql-${PG_MAJOR}-pgtap \
    && pgxn install plpgsql_check \
    && rm -rf /var/lib/apt/lists/*

# Add the extensions to postgres config
RUN echo "shared_preload_libraries = 'pg_cron'" >> /usr/share/postgresql/postgresql.conf.sample

# Copy SQL files
COPY *.sql /docker-entrypoint-initdb.d/

# Set environment variables
ENV POSTGRES_DB=postgres
ENV POSTGRES_USER=postgres
ENV POSTGRES_PASSWORD=postgres

EXPOSE 5432

# Add healthcheck
HEALTHCHECK --interval=10s --timeout=5s --start-period=10s --retries=5 \
    CMD pg_isready -U $POSTGRES_USER -d $POSTGRES_DB || exit 1

#!/bin/bash
set -e

# Wait for PostgreSQL to be ready
echo "Waiting for PostgreSQL..."
while ! pg_isready -h ${POSTGRES_SERVER} -p 5432 -U ${POSTGRES_USER}; do
  sleep 1
done
echo "PostgreSQL is ready!"

# Run migrations
echo "Running migrations..."
alembic upgrade head

# Seed initial data
echo "Seeding initial data..."
python -m scripts.seed_db

# Start the application
echo "Starting application..."
uvicorn app.main:app --host 0.0.0.0 --port 8000

exec "$@"
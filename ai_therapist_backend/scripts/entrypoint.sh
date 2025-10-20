#!/bin/bash
set -e

echo "Starting entrypoint script..."

# Run migrations
echo "Running Alembic migrations..."
alembic upgrade head || {
    echo "ERROR: Alembic migration failed!"
    exit 1
}
echo "Migrations completed successfully"

# Seed initial data (if needed)
if [ -f "scripts/seed_db.py" ]; then
    echo "Seeding initial data..."
    python -m scripts.seed_db || echo "Warning: Seeding failed, continuing..."
fi

# Start the application
echo "Starting application on port ${PORT:-8080}..."
exec uvicorn app.main:app --host 0.0.0.0 --port ${PORT:-8080} --timeout-keep-alive 300
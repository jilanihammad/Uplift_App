from logging.config import fileConfig

import urllib.parse
from sqlalchemy import engine_from_config
from sqlalchemy import pool

from alembic import context

from app.db.base import Base
from app.models import user, assessment, session, message, action_plan, note, reminder, subscription

# After Import models
from app.core.config import settings
import os

# this is the Alembic Config object, which provides
# access to the values within the .ini file in use.
config = context.config


# Set sqlalchemy.url from settings
from app.core.config import settings
#config.set_main_option("sqlalchemy.url", str(settings.SQLALCHEMY_DATABASE_URI))

config.set_main_option("sqlalchemy.url", 
    f"postgresql://postgres:{urllib.parse.quote('7860')}@localhost/ai_therapist_new")
# config.set_main_option("sqlalchemy.url", "postgresql://postgres:7860@localhost/ai_therapist")

print(f"Postgres Server: {settings.POSTGRES_SERVER}")
print(f"Postgres User: {settings.POSTGRES_USER}")
print(f"Postgres DB: {settings.POSTGRES_DB}")
print(f"SQLAlchemy Database URI: {settings.SQLALCHEMY_DATABASE_URI}")

# Interpret the config file for Python logging.
# This line sets up loggers basically.
if config.config_file_name is not None:
    fileConfig(config.config_file_name)

# add your model's MetaData object here
# for 'autogenerate' support
# from myapp import mymodel
# target_metadata = mymodel.Base.metadata
target_metadata = Base.metadata

# other values from the config, defined by the needs of env.py,
# can be acquired:
# my_important_option = config.get_main_option("my_important_option")
# ... etc.

print(f"Connection string: {settings.SQLALCHEMY_DATABASE_URI}")

def run_migrations_offline() -> None:
    """Run migrations in 'offline' mode.

    This configures the context with just a URL
    and not an Engine, though an Engine is acceptable
    here as well.  By skipping the Engine creation
    we don't even need a DBAPI to be available.

    Calls to context.execute() here emit the given string to the
    script output.

    """
    url = config.get_main_option("sqlalchemy.url")
    context.configure(
        url=url,
        target_metadata=target_metadata,
        literal_binds=True,
        dialect_opts={"paramstyle": "named"},
    )

    with context.begin_transaction():
        context.run_migrations()


def run_migrations_online() -> None:
    """Run migrations in 'online' mode.

    In this scenario we need to create an Engine
    and associate a connection with the context.

    """
    
    # Add this before the engine_from_config line
    config_section = config.get_section(config.config_ini_section, {})
    print("Config section:", config_section)
    # And modify your engine_from_config call to print the URL:
    url = config_section.get("sqlalchemy.url")
    print("Database URL:", url)

    
    connectable = engine_from_config(
        config.get_section(config.config_ini_section, {}),
        prefix="sqlalchemy.",
        poolclass=pool.NullPool,
    )

    with connectable.connect() as connection:
        context.configure(
            connection=connection, target_metadata=target_metadata
        )

        with context.begin_transaction():
            context.run_migrations()


if context.is_offline_mode():
    run_migrations_offline()
else:
    run_migrations_online()

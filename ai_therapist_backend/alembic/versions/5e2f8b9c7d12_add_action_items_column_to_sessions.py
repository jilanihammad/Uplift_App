"""add action_items column to sessions

Revision ID: 5e2f8b9c7d12
Revises: 4d421d805e34
Create Date: 2025-06-15 10:30:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

# revision identifiers, used by Alembic.
revision: str = '5e2f8b9c7d12'
down_revision: Union[str, None] = '4d421d805e34'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    # Add action_items column to sessions table
    op.add_column('sessions', sa.Column('action_items', sa.JSON(), nullable=True))


def downgrade() -> None:
    """Downgrade schema."""
    # Remove action_items column from sessions table
    op.drop_column('sessions', 'action_items')
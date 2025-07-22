"""Add subscription fields to users table

Revision ID: d07c48f4a3a8
Revises: 5e2f8b9c7d12
Create Date: 2025-07-20 18:17:05.109356

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'd07c48f4a3a8'
down_revision: Union[str, None] = '5e2f8b9c7d12'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    # Add subscription fields to users table
    op.add_column('users', sa.Column('subscription_tier', sa.String(20), nullable=False, server_default='none'))
    op.add_column('users', sa.Column('subscription_expires_at', sa.DateTime(timezone=True), nullable=True))
    op.add_column('users', sa.Column('subscription_plan_id', sa.String(50), nullable=True))


def downgrade() -> None:
    """Downgrade schema."""
    # Remove subscription fields from users table
    op.drop_column('users', 'subscription_plan_id')
    op.drop_column('users', 'subscription_expires_at')
    op.drop_column('users', 'subscription_tier')

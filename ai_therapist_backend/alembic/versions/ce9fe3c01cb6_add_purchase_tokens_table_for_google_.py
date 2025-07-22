"""Add purchase_tokens table for Google Play webhook mapping

Revision ID: ce9fe3c01cb6
Revises: d07c48f4a3a8
Create Date: 2025-07-20 18:20:01.281004

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'ce9fe3c01cb6'
down_revision: Union[str, None] = 'd07c48f4a3a8'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    # Create purchase_tokens table
    op.create_table(
        'purchase_tokens',
        sa.Column('id', sa.Integer(), nullable=False),
        sa.Column('user_id', sa.Integer(), nullable=False),
        sa.Column('purchase_token', sa.String(255), nullable=False),
        sa.Column('subscription_id', sa.String(50), nullable=False),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=True),
        sa.ForeignKeyConstraint(['user_id'], ['users.id'], ),
        sa.PrimaryKeyConstraint('id')
    )
    op.create_index(op.f('ix_purchase_tokens_id'), 'purchase_tokens', ['id'], unique=False)
    op.create_index(op.f('ix_purchase_tokens_purchase_token'), 'purchase_tokens', ['purchase_token'], unique=True)


def downgrade() -> None:
    """Downgrade schema."""
    # Drop purchase_tokens table
    op.drop_index(op.f('ix_purchase_tokens_purchase_token'), table_name='purchase_tokens')
    op.drop_index(op.f('ix_purchase_tokens_id'), table_name='purchase_tokens')
    op.drop_table('purchase_tokens')

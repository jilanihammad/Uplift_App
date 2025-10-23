"""Add user mood entries table

Revision ID: b7f4d0e1c2a3
Revises: a1b2c3d4e5f6
Create Date: 2025-10-21 10:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

# revision identifiers, used by Alembic.
revision: str = 'b7f4d0e1c2a3'
down_revision: Union[str, None] = 'a1b2c3d4e5f6'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        'user_mood_entries',
        sa.Column('id', postgresql.UUID(as_uuid=True), primary_key=True, nullable=False),
        sa.Column('user_id', sa.Integer(), nullable=False),
        sa.Column('client_entry_id', sa.String(length=64), nullable=False),
        sa.Column('mood', sa.SmallInteger(), nullable=False),
        sa.Column('notes', sa.String(length=512), nullable=True),
        sa.Column('logged_at', sa.DateTime(timezone=True), nullable=False),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
        sa.Column('updated_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
        sa.CheckConstraint('mood >= 0 AND mood <= 5', name='ck_user_mood_entries_mood_range'),
        sa.ForeignKeyConstraint(['user_id'], ['users.id'], name='fk_user_mood_entries_user_id'),
        sa.UniqueConstraint('user_id', 'client_entry_id', name='uq_user_mood_entries_user_client'),
    )
    op.create_index(
        'ix_user_mood_entries_user_logged_at_id',
        'user_mood_entries',
        ['user_id', sa.text('logged_at DESC'), 'id'],
    )


def downgrade() -> None:
    op.drop_index('ix_user_mood_entries_user_logged_at_id', table_name='user_mood_entries')
    op.drop_table('user_mood_entries')

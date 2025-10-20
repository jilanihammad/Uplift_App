"""Add personalization persistence tables

Revision ID: a1b2c3d4e5f6
Revises: 5e2f8b9c7d12
Create Date: 2025-10-19 18:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

# revision identifiers, used by Alembic.
revision: str = 'a1b2c3d4e5f6'
down_revision: Union[str, None] = '5e2f8b9c7d12'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        'user_profiles',
        sa.Column('id', postgresql.UUID(as_uuid=True), primary_key=True, nullable=False),
        sa.Column('user_id', sa.Integer(), nullable=False, unique=True),
        sa.Column('preferred_name', sa.String(), nullable=True),
        sa.Column('pronouns', sa.String(), nullable=True),
        sa.Column('locale', sa.String(), nullable=True),
        sa.Column('version', sa.Integer(), nullable=False, server_default=sa.text('1')),
        sa.Column('updated_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
        sa.ForeignKeyConstraint(['user_id'], ['users.id']),
        sa.UniqueConstraint('user_id', name='uq_user_profiles_user_id')
    )
    op.create_index('ix_user_profiles_updated_at', 'user_profiles', ['updated_at'])

    op.create_table(
        'session_anchors',
        sa.Column('id', postgresql.UUID(as_uuid=True), primary_key=True, nullable=False),
        sa.Column('user_id', sa.Integer(), nullable=False),
        sa.Column('client_anchor_id', sa.String(), nullable=False),
        sa.Column('anchor_text', sa.String(), nullable=False),
        sa.Column('anchor_type', sa.String(), nullable=True),
        sa.Column('confidence', sa.Numeric(3, 2), nullable=True),
        sa.Column('is_deleted', sa.Boolean(), nullable=False, server_default=sa.text('false')),
        sa.Column('last_seen_session_index', sa.Integer(), nullable=True),
        sa.Column('updated_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
        sa.ForeignKeyConstraint(['user_id'], ['users.id']),
        sa.UniqueConstraint('user_id', 'client_anchor_id', name='uq_session_anchors_user_client')
    )
    op.create_index('ix_session_anchors_user_id', 'session_anchors', ['user_id'])
    op.create_index('ix_session_anchors_updated_at', 'session_anchors', ['updated_at'])

    op.create_table(
        'session_summaries',
        sa.Column('id', postgresql.UUID(as_uuid=True), primary_key=True, nullable=False),
        sa.Column('user_id', sa.Integer(), nullable=False),
        sa.Column('session_id', sa.String(), nullable=False),
        sa.Column('summary_json', postgresql.JSONB(), nullable=False),
        sa.Column('updated_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
        sa.ForeignKeyConstraint(['user_id'], ['users.id']),
        sa.UniqueConstraint('user_id', 'session_id', name='uq_session_summaries_user_session')
    )
    op.create_index('ix_session_summaries_user_id', 'session_summaries', ['user_id'])
    op.create_index('ix_session_summaries_session_id', 'session_summaries', ['session_id'])
    op.create_index('ix_session_summaries_updated_at', 'session_summaries', ['updated_at'])


def downgrade() -> None:
    op.drop_index('ix_session_summaries_updated_at', table_name='session_summaries')
    op.drop_index('ix_session_summaries_session_id', table_name='session_summaries')
    op.drop_index('ix_session_summaries_user_id', table_name='session_summaries')
    op.drop_table('session_summaries')

    op.drop_index('ix_session_anchors_updated_at', table_name='session_anchors')
    op.drop_index('ix_session_anchors_user_id', table_name='session_anchors')
    op.drop_table('session_anchors')

    op.drop_index('ix_user_profiles_updated_at', table_name='user_profiles')
    op.drop_table('user_profiles')

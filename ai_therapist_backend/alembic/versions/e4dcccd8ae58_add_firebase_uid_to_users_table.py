"""Add firebase_uid to users table

Revision ID: e4dcccd8ae58
Revises: ce9fe3c01cb6
Create Date: 2025-07-20 22:40:06.647657

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'e4dcccd8ae58'
down_revision: Union[str, None] = 'ce9fe3c01cb6'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    # Step 1: Make email nullable FIRST
    op.alter_column('users', 'email', nullable=True)
    
    # Step 2: Drop the existing unique constraint on email
    op.drop_index('ix_users_email', table_name='users')
    
    # Step 3: Create partial unique index (only for non-null emails)
    op.execute("""
        CREATE UNIQUE INDEX ix_users_email_partial 
        ON users(email) 
        WHERE email IS NOT NULL
    """)
    
    # Step 4: Add firebase_uid column
    op.add_column('users', sa.Column('firebase_uid', sa.String(128), nullable=True))
    
    # Step 5: Create unique index for firebase_uid
    op.create_index('idx_users_firebase_uid', 'users', ['firebase_uid'], unique=True)
    
    # No backfill - users get firebase_uid on next login


def downgrade() -> None:
    """Downgrade schema."""
    # Reverse the changes
    op.drop_index('idx_users_firebase_uid', table_name='users')
    op.drop_column('users', 'firebase_uid')
    
    # Restore original email constraint
    op.execute("DROP INDEX ix_users_email_partial")
    op.create_index('ix_users_email', 'users', ['email'], unique=True)
    op.alter_column('users', 'email', nullable=False)

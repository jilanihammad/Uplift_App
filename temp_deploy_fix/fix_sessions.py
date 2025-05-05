#!/usr/bin/env python
"""
Script to fix the sessions API endpoint in the backend application.
This replaces the mock data in get_sessions with real database queries.
"""

import os
import re
import shutil
import sys

def fix_get_sessions(main_py_path):
    """
    Find the get_sessions function and replace the mock data with database code.
    """
    with open(main_py_path, 'r', encoding='utf-8') as file:
        content = file.read()

    # Find the get_sessions function
    pattern = r'@app\.get\("/sessions", status_code=status\.HTTP_200_OK\).*?async def get_sessions.*?try:.*?if user_id:.*?else:.*?now = datetime\.now\(\)\.isoformat\(\).*?return \[.*?\].*?result = \[\]'
    
    # Use regex with DOTALL flag to match across multiple lines
    match = re.search(pattern, content, re.DOTALL)
    
    if not match:
        print("ERROR: Could not find the get_sessions function in the code.")
        return False
    
    # The matched text to replace
    old_code = match.group(0)
    
    # The new code that uses the database
    new_code = """@app.get("/sessions", status_code=status.HTTP_200_OK)
async def get_sessions(db: DBSession = Depends(get_db), user_id: Optional[int] = None):
    \"\"\"Get all sessions, optionally filtered by user_id\"\"\"
    try:
        logger.info(f"Getting sessions for user {user_id if user_id else 'all users'}")
        
        # Get all sessions - for now we use a default user_id (1) if none is provided
        # In a real implementation with auth, you would use the authenticated user's ID
        sessions = crud_session.get_sessions_by_user(db, user_id or 1)
        
        # Convert SQLAlchemy models to response format
        result = []"""
    
    # Replace the old code with the new code
    new_content = content.replace(old_code, new_code)
    
    # Write the modified content back to the file
    with open(main_py_path, 'w', encoding='utf-8') as file:
        file.write(new_content)
    
    print(f"Successfully updated {main_py_path}")
    return True

if __name__ == "__main__":
    if len(sys.argv) > 1:
        main_py_path = sys.argv[1]
    else:
        main_py_path = "../ai_therapist_backend/app/main.py"
    
    print(f"Fixing get_sessions function in {main_py_path}")
    success = fix_get_sessions(main_py_path)
    if success:
        print("Fix completed successfully.")
    else:
        print("Fix failed.") 
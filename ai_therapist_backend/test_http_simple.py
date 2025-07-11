#!/usr/bin/env python3
"""
Simple HTTP Pooling Test

This script tests the HTTP pooling integration without external dependencies.
"""

import sys
import os

# Add the app to the path
sys.path.insert(0, '/home/jilani/MyApps/Uplift_App/ai_therapist_backend')

try:
    from app.core.http_utils import audit_one_shot_clients
    
    def test_one_shot_audit():
        """Test the one-shot client audit to find remaining issues."""
        print("Testing one-shot client audit...")
        
        findings = audit_one_shot_clients()
        
        print(f"Found {len(findings)} potential one-shot client usages:")
        
        # Filter out test files and known acceptable usage
        production_findings = [
            f for f in findings 
            if not any(exclude in f['file'] for exclude in [
                'test_', 'tests/', '__pycache__', '.pyc', 'cloud_deploy/', 
                'test_enhanced_logging.py', 'test_http_pooling.py', 'test_http_simple.py'
            ])
        ]
        
        print(f"\nProduction code findings: {len(production_findings)}")
        for finding in production_findings:
            print(f"  {finding['file']}:{finding['line']} - {finding['content']}")
        
        # Check if we successfully reduced one-shot clients
        if len(production_findings) == 0:
            print("✓ No one-shot clients found in production code!")
        else:
            print(f"⚠️  {len(production_findings)} one-shot clients still need to be converted")
            
        return len(production_findings)
    
    def main():
        """Run all tests."""
        print("=== HTTP Client Pooling Integration Test ===\n")
        
        remaining_issues = test_one_shot_audit()
        
        print(f"\n=== Test completed: {remaining_issues} issues remaining ===")
        
        return remaining_issues
    
    if __name__ == "__main__":
        exit_code = main()
        sys.exit(exit_code)
        
except Exception as e:
    print(f"Error running HTTP pooling tests: {e}")
    import traceback
    traceback.print_exc()
    sys.exit(1)
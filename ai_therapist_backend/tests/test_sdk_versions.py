"""
Test to verify critical SDK versions are correct.
This ensures the deployed container has the right dependencies.
"""

import pytest
from packaging import version


def test_openai_sdk_version():
    """Verify OpenAI SDK is version 1.85.0 or higher for TTS streaming support."""
    try:
        import openai
        
        current_version = version.parse(openai.__version__)
        required_version = version.parse("1.85.0")
        
        assert current_version >= required_version, \
            f"OpenAI SDK version {openai.__version__} is too old. " \
            f"Version 1.85.0+ required for TTS streaming (format parameter support)."
        
        # Log success for CI/CD visibility
        print(f"✅ OpenAI SDK version check passed: {openai.__version__}")
        
    except ImportError:
        pytest.fail("OpenAI SDK not installed")


def test_exact_openai_version():
    """Verify OpenAI SDK is exactly version 1.95.0 as specified in requirements.txt."""
    try:
        import openai
        
        assert openai.__version__ == "1.95.0", \
            f"OpenAI SDK version {openai.__version__} does not match " \
            f"requirements.txt specification (1.95.0)"
        
        print(f"✅ OpenAI SDK exact version check passed: {openai.__version__}")
        
    except ImportError:
        pytest.fail("OpenAI SDK not installed")


def test_packaging_module_available():
    """Verify packaging module is available for version comparisons."""
    try:
        import packaging
        from packaging import version
        
        # Test basic functionality
        v1 = version.parse("1.85.0")
        v2 = version.parse("1.95.0")
        assert v2 > v1, "Version comparison not working correctly"
        
        print("✅ Packaging module available and working")
        
    except ImportError:
        pytest.fail("Packaging module not installed - required for version checks")


if __name__ == "__main__":
    # Allow running directly for quick checks
    print("Running SDK version tests...")
    
    test_openai_sdk_version()
    test_exact_openai_version()
    test_packaging_module_available()
    
    print("\nAll SDK version tests passed! ✅")
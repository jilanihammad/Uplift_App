import sys
import os
from unittest.mock import MagicMock

# Add project root to path
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))

# Create a mock module for encryption_service
mock_encryption_service = MagicMock()
mock_encryption_service.encrypt = MagicMock(return_value="encrypted_data")
mock_encryption_service.decrypt = MagicMock(return_value="decrypted_data")

# Create the mock module and inject it into sys.modules before imports happen
sys.modules['app.services.encryption_service'] = MagicMock()
sys.modules['app.services.encryption_service'].encryption_service = mock_encryption_service
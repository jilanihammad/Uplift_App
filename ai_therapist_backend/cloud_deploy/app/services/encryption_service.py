from cryptography.fernet import Fernet

class EncryptionService:
    def __init__(self):
        # Generate a key for encryption/decryption
        # In production, securely store and retrieve this key
        self.key = Fernet.generate_key()
        self.cipher = Fernet(self.key)

    def encrypt(self, data: str) -> str:
        """Encrypt the given data."""
        return self.cipher.encrypt(data.encode()).decode()

    def decrypt(self, encrypted_data: str) -> str:
        """Decrypt the given data."""
        return self.cipher.decrypt(encrypted_data.encode()).decode()

# Create a singleton instance of the encryption service
encryption_service = EncryptionService()
import pytest
from unittest.mock import patch
from solai.runner import image_present
import subprocess

def test_image_present_with_digest():
    """Test image_present when Docker returns a digest."""
    with patch('subprocess.check_output') as mock_check_output:
        mock_check_output.return_value = 'sha256:abc123\n'
        assert image_present('test:latest') == True
        mock_check_output.assert_called_once_with(
            "docker images --no-trunc --format '{{.Digest}}' test:latest",
            shell=True, text=True
        )

def test_image_present_without_digest():
    """Test image_present when Docker returns empty string (image not found)."""
    with patch('subprocess.check_output') as mock_check_output:
        mock_check_output.return_value = '\n'
        assert image_present('test:latest') == False
        mock_check_output.assert_called_once_with(
            "docker images --no-trunc --format '{{.Digest}}' test:latest",
            shell=True, text=True
        )

def test_image_present_command_error():
    """Test image_present when Docker command fails."""
    with patch('subprocess.check_output') as mock_check_output:
        mock_check_output.side_effect = subprocess.CalledProcessError(1, 'cmd')
        with pytest.raises(subprocess.CalledProcessError):
            image_present('test:latest') 
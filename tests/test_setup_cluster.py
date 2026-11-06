"""Tests for aws-eks-protection setup_cluster.py status polling fix.

SOLAR-2338: `while update_response['update']['status'] == 'InProgress'`

The original code used Python's `in` operator against a string literal:
    while status in 'InProgress'
which checks whether `status` is a *substring* of the string 'InProgress'.
This means statuses like 'P', 'In', or 'gress' would satisfy the condition
and loop forever. The fix uses strict equality instead.
"""
import importlib.util
import os
import sys
from unittest.mock import MagicMock, patch, call

import pytest

# ---------------------------------------------------------------------------
# Environment setup (module reads os.environ at import time)
# ---------------------------------------------------------------------------

os.environ.update({
    "AWS_REGION": "us-east-1",
    "SCOPE": "account",
    "EKS_CLUSTER_NAME": "test-cluster",
    "ACCOUNT_ID": "123456789012",
    "SWITCH_ROLE": "test-role",
    "NAT_IP": "1.2.3.4",
    "TASK_ARN": "arn:aws:ecs:us-east-1:123456789012:task/abc",
    "PARTITION": "aws",
})

_MODULE_PATH = os.path.join(os.path.dirname(__file__), "../setup_cluster.py")


def _active_cluster_mock():
    """Return a mock EKS client whose describe_cluster returns ACTIVE immediately.

    Used for the module-level calls that run on import so they complete without
    sleeping or looping.  publicAccessCidrs includes 0.0.0.0/0 so setup_cluster
    skips the update path during import.
    """
    mock_eks = MagicMock()
    mock_eks.describe_cluster.return_value = {
        "cluster": {
            "status": "ACTIVE",
            "resourcesVpcConfig": {"publicAccessCidrs": ["0.0.0.0/0"]},
        }
    }
    return mock_eks


@pytest.fixture(scope="module")
def sc():
    """Import setup_cluster with module-level boto3 calls safely mocked."""
    with patch("boto3.client", return_value=_active_cluster_mock()):
        spec = importlib.util.spec_from_file_location("setup_cluster", _MODULE_PATH)
        mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mod)
    return mod


# ---------------------------------------------------------------------------
# Status polling loop
# ---------------------------------------------------------------------------

class TestUpdateStatusLoop:
    @pytest.fixture(autouse=True)
    def no_sleep(self):
        with patch("time.sleep"):
            yield

    def test_loop_polls_until_successful(self, sc):
        """The while loop continues while status is 'InProgress' and exits
        once it becomes 'Successful'."""
        mock_eks = _active_cluster_mock()
        mock_eks.update_cluster_config.return_value = {"update": {"id": "upd-1"}}
        mock_eks.describe_update.side_effect = [
            {"update": {"status": "InProgress"}},
            {"update": {"status": "Successful"}},
        ]

        sc.setup_cluster(mock_eks, [])

        # First call before the loop, second call inside the loop on re-poll
        assert mock_eks.describe_update.call_count == 2

    def test_loop_does_not_run_when_immediately_complete(self, sc):
        """If the first describe_update is already Successful, the loop body
        never executes and describe_update is called exactly once."""
        mock_eks = _active_cluster_mock()
        mock_eks.update_cluster_config.return_value = {"update": {"id": "upd-1"}}
        mock_eks.describe_update.return_value = {"update": {"status": "Successful"}}

        sc.setup_cluster(mock_eks, [])

        assert mock_eks.describe_update.call_count == 1

    def test_loop_polls_multiple_times_before_completing(self, sc):
        """The loop re-polls as many times as needed."""
        mock_eks = _active_cluster_mock()
        mock_eks.update_cluster_config.return_value = {"update": {"id": "upd-1"}}
        mock_eks.describe_update.side_effect = [
            {"update": {"status": "InProgress"}},
            {"update": {"status": "InProgress"}},
            {"update": {"status": "InProgress"}},
            {"update": {"status": "Successful"}},
        ]

        sc.setup_cluster(mock_eks, [])

        assert mock_eks.describe_update.call_count == 4

    def test_skips_update_when_cidr_already_open(self, sc):
        """When cidrs_list contains 0.0.0.0/0 no update is issued."""
        mock_eks = _active_cluster_mock()

        sc.setup_cluster(mock_eks, ["0.0.0.0/0"])

        mock_eks.update_cluster_config.assert_not_called()

    def test_old_substring_bug_would_have_looped_on_partial_status(self):
        """Document the old bug: substrings of 'InProgress' satisfy
        `status in 'InProgress'` but not `status == 'InProgress'`."""
        for partial in ("P", "In", "gress", "I"):
            # Old code would have continued looping on these
            assert (partial in "InProgress") is True
            # New code correctly exits the loop
            assert (partial == "InProgress") is False

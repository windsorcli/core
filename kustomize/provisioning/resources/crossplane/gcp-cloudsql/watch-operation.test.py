"""Unit tests for gcp-cloudsql/watch-operation.yaml's embedded script.

Run via scripts/test-composition-functions.sh, which extracts the script's
text into a real .py file and points COMPOSITION_SCRIPT at it. request/
response are faked well enough to exercise operate()'s branching, not just
the pure builder functions.
"""

import base64
import collections
import importlib.util
import os
import sys
import types
import unittest


class _DesiredResource:
    def __init__(self):
        self.resource = {}
        self.ready = False


class _FakeResponse:
    def __init__(self):
        self.desired = types.SimpleNamespace(
            resources=collections.defaultdict(_DesiredResource)
        )
        self.output = None
        self.requirements = []


def _stub_crossplane_sdk():
    crossplane_mod = types.ModuleType("crossplane")
    function_mod = types.ModuleType("crossplane.function")

    function_mod.request = types.SimpleNamespace(
        get_required_resource=lambda req, name: req.get(name)
    )

    def require_resources(rsp, **kwargs):
        rsp.requirements.append(kwargs)

    def set_output(rsp, output):
        rsp.output = output

    function_mod.response = types.SimpleNamespace(
        require_resources=require_resources, set_output=set_output
    )
    proto_mod = types.ModuleType("crossplane.function.proto")
    proto_v1_mod = types.ModuleType("crossplane.function.proto.v1")
    run_function_pb2_mod = types.SimpleNamespace(
        RunFunctionRequest=object,
        RunFunctionResponse=object,
    )

    crossplane_mod.function = function_mod
    function_mod.proto = proto_mod
    proto_mod.v1 = proto_v1_mod
    proto_v1_mod.run_function_pb2 = run_function_pb2_mod

    sys.modules["crossplane"] = crossplane_mod
    sys.modules["crossplane.function"] = function_mod
    sys.modules["crossplane.function.proto"] = proto_mod
    sys.modules["crossplane.function.proto.v1"] = proto_v1_mod
    sys.modules["crossplane.function.proto.v1.run_function_pb2"] = (
        run_function_pb2_mod
    )


_stub_crossplane_sdk()

_spec = importlib.util.spec_from_file_location(
    "watch_operation", os.environ["COMPOSITION_SCRIPT"]
)
watch_operation = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(watch_operation)


def _b64(value):
    return base64.b64encode(value.encode()).decode()


def _server(name="demo-db", uid="abc-123", endpoint="10.0.0.5"):
    return {
        "apiVersion": "sql.gcp.upbound.io/v1beta2",
        "kind": "DatabaseInstance",
        "metadata": {"name": name, "uid": uid},
        "status": {"atProvider": {"privateIpAddress": endpoint}},
    }


class NameHelperTests(unittest.TestCase):
    def test_admin_secret_name_derives_from_server_name(self):
        self.assertEqual(
            watch_operation.admin_secret_name("demo-db"), "demo-db-admin-credentials"
        )

    def test_admin_user_name_derives_from_server_name(self):
        self.assertEqual(watch_operation.admin_user_name("demo-db"), "demo-db-admin")

    def test_connection_secret_name_derives_from_server_name(self):
        self.assertEqual(
            watch_operation.connection_secret_name("demo-db"), "demo-db-connection"
        )


class BuildAdminSecretTests(unittest.TestCase):
    def test_username_matches_admin_user_name(self):
        secret = watch_operation.build_admin_secret("demo-db", [])
        self.assertEqual(secret["stringData"]["username"], "demo-db-admin")

    def test_lands_in_the_admin_namespace(self):
        secret = watch_operation.build_admin_secret("demo-db", [])
        self.assertEqual(secret["metadata"]["namespace"], "system-database")


class BuildAdminUserTests(unittest.TestCase):
    def test_references_its_own_generated_secret(self):
        user = watch_operation.build_admin_user("demo-db", "demo-db-admin", [])
        self.assertEqual(
            user["spec"]["forProvider"]["passwordSecretRef"],
            {"name": "demo-db-admin-credentials", "namespace": "system-database", "key": "password"},
        )


class OperateCreatesOwnAdminIdentityTests(unittest.TestCase):
    def test_mints_admin_secret_when_nothing_exists_yet(self):
        req = {"ops.crossplane.io/watched-resource": _server(), "admin-user": None}
        rsp = _FakeResponse()

        watch_operation.operate(req, rsp)

        secret = rsp.desired.resources["admin-secret"].resource
        self.assertEqual(secret["metadata"]["name"], "demo-db-admin-credentials")
        self.assertIn("waiting", rsp.output)

    def test_creates_admin_user_once_its_own_secret_exists(self):
        req = {
            "ops.crossplane.io/watched-resource": _server(),
            "admin-user": None,
            "admin-secret": {
                "data": {"username": _b64("demo-db-admin"), "password": _b64("generated-pw")}
            },
        }
        rsp = _FakeResponse()

        watch_operation.operate(req, rsp)

        user = rsp.desired.resources["admin-user"].resource
        self.assertEqual(
            user["spec"]["forProvider"]["passwordSecretRef"]["name"],
            "demo-db-admin-credentials",
        )


class OperateDefersToExistingAdminUserTests(unittest.TestCase):
    def test_reads_the_password_from_its_own_admin_users_secret_ref(self):
        req = {
            "ops.crossplane.io/watched-resource": _server(),
            "admin-user": {
                "spec": {
                    "forProvider": {
                        "passwordSecretRef": {
                            "name": "demo-db-admin-credentials",
                            "namespace": "system-database",
                            "key": "password",
                        }
                    }
                }
            },
            "admin-secret": {
                "data": {"username": _b64("demo-db-admin"), "password": _b64("generated-pw")}
            },
        }
        rsp = _FakeResponse()

        watch_operation.operate(req, rsp)

        conn = rsp.desired.resources["connection-secret"].resource
        self.assertEqual(conn["stringData"]["password"], "generated-pw")

    def test_a_consumer_owned_user_is_never_overwritten_with_a_new_secret(self):
        # A consumer already rendered its own demo-db-admin User pointing at
        # a Secret this WatchOperation didn't create.
        req = {
            "ops.crossplane.io/watched-resource": _server(),
            "admin-user": {
                "spec": {
                    "forProvider": {
                        "passwordSecretRef": {
                            "name": "consumer-admin-secret",
                            "namespace": "consumer-ns",
                            "key": "pw",
                        }
                    }
                }
            },
            "admin-secret": {
                "data": {"username": _b64("demo-db-admin"), "pw": _b64("consumer-owned-pw")}
            },
        }
        rsp = _FakeResponse()

        watch_operation.operate(req, rsp)

        # No competing admin-secret was minted for this instance.
        self.assertEqual(rsp.desired.resources["admin-secret"].resource, {})
        conn = rsp.desired.resources["connection-secret"].resource
        self.assertEqual(conn["stringData"]["password"], "consumer-owned-pw")

    def test_waits_when_the_referenced_secret_has_no_matching_key_yet(self):
        req = {
            "ops.crossplane.io/watched-resource": _server(),
            "admin-user": {
                "spec": {
                    "forProvider": {
                        "passwordSecretRef": {
                            "name": "consumer-admin-secret",
                            "namespace": "consumer-ns",
                            "key": "pw",
                        }
                    }
                }
            },
            "admin-secret": {"data": {"username": _b64("demo-db-admin")}},
        }
        rsp = _FakeResponse()

        watch_operation.operate(req, rsp)

        self.assertNotIn("connection-secret", rsp.desired.resources)
        self.assertIn("waiting", rsp.output)

    def test_builds_the_cluster_provider_config_once_fully_resolved(self):
        req = {
            "ops.crossplane.io/watched-resource": _server(),
            "admin-user": {
                "spec": {
                    "forProvider": {
                        "passwordSecretRef": {
                            "name": "demo-db-admin-credentials",
                            "namespace": "system-database",
                            "key": "password",
                        }
                    }
                }
            },
            "admin-secret": {
                "data": {"username": _b64("demo-db-admin"), "password": _b64("generated-pw")}
            },
        }
        rsp = _FakeResponse()

        watch_operation.operate(req, rsp)

        provider_config = rsp.desired.resources["cluster-provider-config"].resource
        self.assertEqual(provider_config["metadata"]["name"], "demo-db")
        self.assertEqual(rsp.output, {"providerConfig": "demo-db"})


if __name__ == "__main__":
    unittest.main()

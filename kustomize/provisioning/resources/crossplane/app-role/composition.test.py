"""Unit tests for app-role/composition.yaml's embedded script.

Run via scripts/test-composition-functions.sh, which extracts the script's
text into a real .py file and points COMPOSITION_SCRIPT at it. Only the
pure builder functions are exercised here; compose() itself touches the
Crossplane SDK's protobuf types and is covered by live reconciliation
instead.
"""

import importlib.util
import os
import sys
import types
import unittest


def _stub_crossplane_sdk():
    # The real SDK isn't a repo dependency; only compose()'s imports need
    # it to exist, not the pure functions this file actually exercises.
    crossplane_mod = types.ModuleType("crossplane")
    function_mod = types.ModuleType("crossplane.function")
    function_mod.resource = types.SimpleNamespace()
    function_mod.response = types.SimpleNamespace()
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
    "composition", os.environ["COMPOSITION_SCRIPT"]
)
composition = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(composition)


class SecretNameTests(unittest.TestCase):
    def test_derives_from_the_role_name(self):
        self.assertEqual(
            composition.secret_name("demo-app"), "demo-app-credentials"
        )


class BuildRoleTests(unittest.TestCase):
    def test_references_the_instances_cluster_provider_config(self):
        role = composition.build_role("demo-app", "demo-database", "demo-db")
        self.assertEqual(
            role["spec"]["providerConfigRef"],
            {"kind": "ClusterProviderConfig", "name": "demo-db"},
        )

    def test_is_a_login_role_writing_a_derived_secret(self):
        role = composition.build_role("demo-app", "demo-database", "demo-db")
        self.assertTrue(role["spec"]["forProvider"]["privileges"]["login"])
        self.assertEqual(
            role["spec"]["writeConnectionSecretToRef"]["name"],
            "demo-app-credentials",
        )

    def test_never_deletes_the_postgres_role(self):
        role = composition.build_role("demo-app", "demo-database", "demo-db")
        self.assertNotIn("Delete", role["spec"]["managementPolicies"])


class BuildGrantTests(unittest.TestCase):
    def test_grants_all_privileges_on_the_named_database(self):
        grant = composition.build_grant(
            "demo-app", "demo-database", "demo-db", "demo"
        )
        self.assertEqual(
            grant["spec"]["forProvider"],
            {"role": "demo-app", "database": "demo", "privileges": ["ALL"]},
        )

    def test_name_does_not_collide_with_the_role(self):
        grant = composition.build_grant(
            "demo-app", "demo-database", "demo-db", "demo"
        )
        self.assertEqual(grant["metadata"]["name"], "demo-app-database")


class BuildStatusTests(unittest.TestCase):
    def test_reports_the_secret_and_role_name(self):
        status = composition.build_status("demo-app", "demo-database")
        self.assertEqual(
            status,
            {
                "connectionSecretRef": {
                    "name": "demo-app-credentials",
                    "namespace": "demo-database",
                },
                "roleName": "demo-app",
            },
        )


if __name__ == "__main__":
    unittest.main()

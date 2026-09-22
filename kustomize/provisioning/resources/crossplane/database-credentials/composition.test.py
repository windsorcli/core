"""Unit tests for database-credentials/composition.yaml's embedded script.

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
    function_mod.request = types.SimpleNamespace()
    function_mod.resource = types.SimpleNamespace()
    function_mod.response = types.SimpleNamespace(
        fatal=lambda *a, **k: None,
        require_resources=lambda *a, **k: None,
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
    "composition", os.environ["COMPOSITION_SCRIPT"]
)
composition = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(composition)


class SlugifyTests(unittest.TestCase):
    def test_replaces_underscores_and_lowercases(self):
        self.assertEqual(composition.slugify("pg_monitor"), "pg-monitor")

    def test_leaves_already_valid_names_unchanged(self):
        self.assertEqual(composition.slugify("demo-app"), "demo-app")


class ResolveRoleNameTests(unittest.TestCase):
    def test_explicit_role_name_wins(self):
        self.assertEqual(
            composition.resolve_role_name("monitor", "demo-db-monitor"),
            "monitor",
        )

    def test_defaults_to_the_claims_own_name(self):
        self.assertEqual(
            composition.resolve_role_name(None, "demo-app"), "demo-app"
        )


class AdminCredentialsSecretNameTests(unittest.TestCase):
    def test_matches_the_documented_convention(self):
        self.assertEqual(
            composition.admin_credentials_secret_name("demo-db"),
            "demo-db-admin-credentials",
        )


class BuildProviderConfigUsageTests(unittest.TestCase):
    def test_of_targets_a_cluster_scoped_instance(self):
        usage = composition.build_provider_config_usage(
            "demo-db",
            "",
            "demo-database",
            "rds.aws.upbound.io/v1beta3",
            "Instance",
        )
        self.assertEqual(
            usage["spec"]["of"],
            {
                "apiVersion": "rds.aws.upbound.io/v1beta3",
                "kind": "Instance",
                "resourceRef": {"name": "demo-db", "namespace": ""},
            },
        )

    def test_of_targets_a_namespaced_instance_in_its_own_namespace(self):
        usage = composition.build_provider_config_usage(
            "demo-db",
            "some-instance-namespace",
            "demo-database",
            "rds.aws.upbound.io/v1beta3",
            "Instance",
        )
        self.assertEqual(
            usage["spec"]["of"]["resourceRef"],
            {"name": "demo-db", "namespace": "some-instance-namespace"},
        )

    def test_by_targets_the_provider_config(self):
        usage = composition.build_provider_config_usage(
            "demo-db",
            "",
            "demo-database",
            "rds.aws.upbound.io/v1beta3",
            "Instance",
        )
        self.assertEqual(
            usage["spec"]["by"],
            {
                "apiVersion": "postgresql.sql.m.crossplane.io/v1alpha1",
                "kind": "ProviderConfig",
                "resourceRef": {"name": "provider-sql-demo-db"},
            },
        )

    def test_replays_deletion(self):
        usage = composition.build_provider_config_usage(
            "demo-db",
            "",
            "demo-database",
            "rds.aws.upbound.io/v1beta3",
            "Instance",
        )
        self.assertTrue(usage["spec"]["replayDeletion"])


class BuildRoleTests(unittest.TestCase):
    def test_k8s_name_sanitized_external_name_keeps_real_role(self):
        role = composition.build_role(
            "demo_monitor",
            "demo-monitor",
            "demo-database",
            "demo-db",
            "demo-monitor-credentials",
        )
        self.assertEqual(role["metadata"]["name"], "demo-monitor")
        self.assertEqual(
            role["metadata"]["annotations"]["crossplane.io/external-name"],
            "demo_monitor",
        )
        self.assertEqual(
            role["spec"]["writeConnectionSecretToRef"]["name"],
            "demo-monitor-credentials",
        )

    def test_writes_to_the_given_secret_name(self):
        role = composition.build_role(
            "demo-app", "demo-app", "demo-database", "demo-db", "custom-name"
        )
        self.assertEqual(
            role["spec"]["writeConnectionSecretToRef"]["name"], "custom-name"
        )

    def test_uses_orphan_management_policies(self):
        role = composition.build_role(
            "demo-app",
            "demo-app",
            "demo-database",
            "demo-db",
            "demo-app-credentials",
        )
        self.assertEqual(
            role["spec"]["managementPolicies"], composition.ORPHAN_POLICIES
        )


class BuildGrantTests(unittest.TestCase):
    def test_sanitizes_k8s_name_preserves_real_role_and_member_of(self):
        grant_slug, grant = composition.build_grant(
            "demo_monitor",
            "demo-monitor",
            "system-database",
            "demo-db",
            "pg_monitor",
        )
        self.assertEqual(grant_slug, "pg-monitor")
        self.assertEqual(
            grant["metadata"]["name"], "demo-monitor-pg-monitor"
        )
        self.assertEqual(
            grant["spec"]["forProvider"]["role"], "demo_monitor"
        )
        self.assertEqual(
            grant["spec"]["forProvider"]["memberOf"], "pg_monitor"
        )


class BuildStatusTests(unittest.TestCase):
    def test_includes_database_name_when_set(self):
        status = composition.build_status(
            "demo-app", "demo-database", "demo", "demo-app-credentials"
        )
        self.assertEqual(status["databaseName"], "demo")
        self.assertEqual(
            status["connectionSecretRef"],
            {"name": "demo-app-credentials", "namespace": "demo-database"},
        )

    def test_omits_database_name_when_unset(self):
        status = composition.build_status(
            "demo-db-monitor",
            "system-database",
            None,
            "demo-db-monitor-credentials",
        )
        self.assertNotIn("databaseName", status)

    def test_uses_the_given_secret_name(self):
        status = composition.build_status(
            "demo-app", "demo-database", "demo", "custom-name"
        )
        self.assertEqual(status["connectionSecretRef"]["name"], "custom-name")


class DriverFactsTests(unittest.TestCase):
    def test_every_xrd_target_kind_has_facts(self):
        # Keep in sync with xrd.yaml's spec.target.kind enum.
        for kind in ("Instance", "FlexibleServer", "DatabaseInstance"):
            self.assertIn(kind, composition.DRIVER_FACTS)


if __name__ == "__main__":
    unittest.main()

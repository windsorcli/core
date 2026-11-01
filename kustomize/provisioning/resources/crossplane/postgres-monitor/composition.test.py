"""Unit tests for postgres-monitor/composition.yaml's embedded script.

Run via scripts/test-composition-functions.sh, which extracts the script's
text into a real .py file and points COMPOSITION_SCRIPT at it. Builder
functions are exercised directly. compose() is exercised with fakes where
it assigns Resource.ready, because that field is a protobuf enum.
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
    function_mod.response = types.SimpleNamespace()
    proto_mod = types.ModuleType("crossplane.function.proto")
    proto_v1_mod = types.ModuleType("crossplane.function.proto.v1")
    run_function_pb2_mod = types.SimpleNamespace(
        RunFunctionRequest=object,
        RunFunctionResponse=object,
        READY_TRUE=1,
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


class MonitorRoleNameTests(unittest.TestCase):
    def test_derives_from_the_server_name(self):
        self.assertEqual(
            composition.monitor_role_name("demo-db"), "demo-db-monitor"
        )


class SecretNameTests(unittest.TestCase):
    def test_derives_from_the_role_name(self):
        self.assertEqual(
            composition.secret_name("demo-db-monitor"),
            "demo-db-monitor-credentials",
        )


class BuildMonitorRoleTests(unittest.TestCase):
    def test_references_the_servers_cluster_provider_config(self):
        role = composition.build_monitor_role("demo-db")
        self.assertEqual(
            role["spec"]["providerConfigRef"],
            {"kind": "ClusterProviderConfig", "name": "demo-db"},
        )

    def test_is_a_login_role_writing_a_derived_secret(self):
        role = composition.build_monitor_role("demo-db")
        self.assertTrue(role["spec"]["forProvider"]["privileges"]["login"])
        self.assertEqual(
            role["spec"]["writeConnectionSecretToRef"]["name"],
            "demo-db-monitor-credentials",
        )

    def test_external_name_is_the_shared_monitor_role(self):
        role = composition.build_monitor_role("demo-db")
        self.assertEqual(
            role["metadata"]["annotations"]["crossplane.io/external-name"],
            "monitor",
        )

    def test_never_deletes_the_postgres_role(self):
        role = composition.build_monitor_role("demo-db")
        self.assertNotIn("Delete", role["spec"]["managementPolicies"])


class BuildMonitorGrantTests(unittest.TestCase):
    def test_grants_pg_monitor_membership(self):
        grant = composition.build_monitor_grant("demo-db")
        self.assertEqual(
            grant["spec"]["forProvider"],
            {"role": "monitor", "memberOf": "pg_monitor"},
        )

    def test_references_the_servers_cluster_provider_config(self):
        grant = composition.build_monitor_grant("demo-db")
        self.assertEqual(
            grant["spec"]["providerConfigRef"],
            {"kind": "ClusterProviderConfig", "name": "demo-db"},
        )

    def test_never_deletes_the_grant(self):
        grant = composition.build_monitor_grant("demo-db")
        self.assertNotIn("Delete", grant["spec"]["managementPolicies"])


class BuildExporterDeploymentTests(unittest.TestCase):
    def test_reads_connection_fields_from_the_named_secret(self):
        deployment = composition.build_exporter_deployment(
            "demo-db-monitor", "demo-db-monitor-credentials"
        )
        env = {
            e["name"]: e["valueFrom"]["secretKeyRef"]
            for e in deployment["spec"]["template"]["spec"]["containers"][0]["env"]
            if "valueFrom" in e
        }
        self.assertEqual(env["PGHOST"]["name"], "demo-db-monitor-credentials")
        self.assertEqual(env["PGHOST"]["key"], "endpoint")
        self.assertEqual(env["DATA_SOURCE_USER"]["key"], "username")
        self.assertEqual(env["DATA_SOURCE_PASS"]["key"], "password")

    def test_runs_as_non_root(self):
        deployment = composition.build_exporter_deployment(
            "demo-db-monitor", "demo-db-monitor-credentials"
        )
        security_context = deployment["spec"]["template"]["spec"]["containers"][0][
            "securityContext"
        ]
        self.assertTrue(security_context["runAsNonRoot"])
        self.assertFalse(security_context["allowPrivilegeEscalation"])


class BuildExporterServiceTests(unittest.TestCase):
    def test_selects_the_exporter_pod(self):
        service = composition.build_exporter_service("demo-db-monitor")
        self.assertEqual(
            service["spec"]["selector"], {"app": "demo-db-monitor-exporter"}
        )


class ComposeReadyTests(unittest.TestCase):
    def test_marks_ready_resources_with_the_proto_enum(self):
        class Observed:
            def __init__(self):
                self.resource = {}

        class Desired:
            def __init__(self):
                self.resource = {}
                self.ready = None

        observed = {
            "monitor-role": Observed(),
            "monitor-grant": Observed(),
        }
        desired = {
            name: Desired()
            for name in (
                "monitor-role",
                "monitor-grant",
                "exporter-deployment",
                "exporter-service",
                "exporter-podmonitor",
            )
        }
        req = types.SimpleNamespace(
            observed=types.SimpleNamespace(
                composite=types.SimpleNamespace(
                    resource={
                        "spec": {
                            "serverName": "demo-db",
                            "serverApiVersion": "sql.gcp.upbound.io/v1beta2",
                            "serverKind": "DatabaseInstance",
                        },
                    }
                ),
                resources=observed,
            )
        )
        rsp = types.SimpleNamespace(
            desired=types.SimpleNamespace(resources=desired)
        )
        composition.resource.struct_to_dict = lambda value: value
        composition.resource.get_condition = lambda obj, name: types.SimpleNamespace(
            status="True"
        )
        composition.request.get_required_resource = lambda req, name: {
            "metadata": {}
        }
        composition.response.require_resources = lambda *args, **kwargs: None

        composition.compose(req, rsp)

        self.assertEqual(desired["monitor-role"].ready, composition.fnv1.READY_TRUE)
        self.assertEqual(desired["monitor-grant"].ready, composition.fnv1.READY_TRUE)
        self.assertEqual(
            desired["monitor-grant"].resource["spec"]["forProvider"]["memberOf"],
            "pg_monitor",
        )


class BuildExporterPodMonitorTests(unittest.TestCase):
    def test_relabels_to_the_server_name(self):
        podmonitor = composition.build_exporter_podmonitor(
            "demo-db-monitor", "demo-db"
        )
        relabeling = podmonitor["spec"]["podMetricsEndpoints"][0]["relabelings"][0]
        self.assertEqual(relabeling["targetLabel"], "instance")
        self.assertEqual(relabeling["replacement"], "demo-db")


if __name__ == "__main__":
    unittest.main()

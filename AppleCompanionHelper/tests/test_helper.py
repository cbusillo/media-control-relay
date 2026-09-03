import asyncio
import json
import tempfile
import unittest
from pathlib import Path

from helper import (
    MAX_FRAME_BYTES,
    HelperError,
    result,
    run,
    serve_client,
    validate_socket_path,
    watch_parent_process,
)


class FakeController:
    def __init__(self):
        self.operations = []
        self.closed = False

    async def handle(self, operation):
        self.operations.append(operation)
        if operation.get("operation") == "discover":
            return result("dormant", targets=[{"id": "fixture", "name": "Living Room"}])
        if operation.get("operation") == "beginPairing":
            return result("pairingRequired")
        if operation.get("operation") == "finishPairing":
            return result(
                "ready",
                capabilities=["navigation"],
                secret={"host": "fixture", "identifier": None, "credentials": "opaque"},
            )
        if operation.get("operation") == "connect":
            return result(
                "ready",
                capabilities=["navigation"],
                secret=operation["secret"],
            )
        if operation.get("operation") == "fail":
            raise HelperError("unsupportedAction")
        return result("ready", capabilities=["navigation"])

    async def close(self):
        self.closed = True
        return None


class FakeParentPidObserver:
    def __init__(self, values):
        self.values = iter(values)
        self.calls = 0

    def __call__(self):
        self.calls += 1
        return next(self.values)


class HelperProtocolTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.controller = FakeController()
        self.server = await asyncio.start_server(
            lambda reader, writer: serve_client(reader, writer, self.controller),
            "127.0.0.1",
            0,
            limit=MAX_FRAME_BYTES + 1,
        )
        self.host, self.port = self.server.sockets[0].getsockname()[:2]

    async def asyncTearDown(self):
        self.server.close()
        await self.server.wait_closed()

    async def request(self, operation, request_id=1, generation=0):
        reader, writer = await asyncio.open_connection(self.host, self.port)
        writer.write(
            json.dumps(
                {
                    "kind": "request",
                    "request": {
                        "id": request_id,
                        "generation": generation,
                        "operation": operation,
                    },
                }
            ).encode()
            + b"\n"
        )
        await writer.drain()
        response = json.loads(await reader.readline())
        writer.close()
        await writer.wait_closed()
        return response

    async def test_correlates_request_id_and_generation(self):
        response = await self.request({"operation": "status"}, request_id=41, generation=7)
        self.assertEqual(response["reply"]["id"], 41)
        self.assertEqual(response["reply"]["generation"], 7)

    async def test_shared_swift_wire_fixture_matches_helper(self):
        fixture_path = (
            Path(__file__).parents[2]
            / "Tests"
            / "AppleCompanionSupportTests"
            / "Fixtures"
            / "wire-contract.json"
        )
        fixture = json.loads(fixture_path.read_text())
        request = fixture["request"]["request"]
        response = await self.request(
            request["operation"],
            request_id=request["id"],
            generation=request["generation"],
        )
        self.assertEqual(response, fixture["reply"])

    async def test_discovery_returns_only_bounded_display_records(self):
        response = await self.request({"operation": "discover"})
        self.assertEqual(response["reply"]["targets"], [{"id": "fixture", "name": "Living Room"}])
        self.assertIsNone(response["reply"]["secret"])

    async def test_pairing_is_two_correlated_requests(self):
        begin = {"operation": "beginPairing", "targetID": "fixture"}
        finish = {"operation": "finishPairing", "pin": 1234}
        begin_response = await self.request(begin, request_id=5, generation=2)
        finish_response = await self.request(finish, request_id=6, generation=2)
        self.assertEqual(begin_response["reply"]["state"], "pairingRequired")
        self.assertEqual(finish_response["reply"]["state"], "ready")
        self.assertEqual(finish_response["reply"]["secret"]["credentials"], "opaque")
        self.assertEqual(self.controller.operations, [begin, finish])

    async def test_errors_are_bounded_categories(self):
        response = await self.request({"operation": "fail"})
        self.assertEqual(response["reply"]["error"], "unsupportedAction")
        self.assertNotIn("traceback", json.dumps(response).lower())

    async def test_malformed_frame_fails_closed(self):
        reader, writer = await asyncio.open_connection(self.host, self.port)
        writer.write(b"not-json\n")
        await writer.drain()
        self.assertEqual(await reader.read(), b"")
        writer.close()
        await writer.wait_closed()

    async def test_oversized_frame_fails_closed(self):
        reader, writer = await asyncio.open_connection(self.host, self.port)
        writer.write(b"{" + b"x" * MAX_FRAME_BYTES + b"}\n")
        await writer.drain()
        self.assertEqual(await reader.read(), b"")
        writer.close()
        await writer.wait_closed()

    async def test_unix_socket_is_owner_only_and_cleans_up(self):
        with tempfile.TemporaryDirectory() as directory:
            socket_path = Path(directory) / "companion.sock"
            task = asyncio.create_task(run(socket_path, self.controller))
            for _ in range(100):
                if socket_path.exists():
                    break
                await asyncio.sleep(0.001)
            self.assertTrue(socket_path.exists())
            self.assertEqual(socket_path.stat().st_mode & 0o777, 0o600)

            reader, writer = await asyncio.open_unix_connection(str(socket_path))
            writer.write(
                json.dumps(
                    {
                        "kind": "request",
                        "request": {
                            "id": 6,
                            "generation": 3,
                            "operation": {"operation": "status"},
                        },
                    }
                ).encode()
                + b"\n"
            )
            await writer.drain()
            response = json.loads(await reader.readline())
            self.assertEqual(response["reply"]["id"], 6)
            writer.close()
            await writer.wait_closed()

            task.cancel()
            await task
            self.assertFalse(socket_path.exists())

    async def test_unix_socket_allows_only_one_active_client(self):
        with tempfile.TemporaryDirectory() as directory:
            socket_path = Path(directory) / "companion.sock"
            task = asyncio.create_task(run(socket_path, self.controller))
            for _ in range(100):
                if socket_path.exists():
                    break
                await asyncio.sleep(0.001)

            first_reader, first_writer = await asyncio.open_unix_connection(str(socket_path))
            second_reader, second_writer = await asyncio.open_unix_connection(str(socket_path))
            self.assertEqual(await second_reader.read(), b"")
            second_writer.close()
            await second_writer.wait_closed()
            first_writer.close()
            await first_writer.wait_closed()
            self.assertEqual(await first_reader.read(), b"")

            task.cancel()
            await task

    async def test_parent_watchdog_stops_helper_when_parent_pid_changes(self):
        with tempfile.TemporaryDirectory() as directory:
            socket_path = Path(directory) / "companion.sock"
            observer = FakeParentPidObserver([1234, 1234, 4321])
            task = asyncio.create_task(
                run(
                    socket_path,
                    self.controller,
                    observe_parent_pid=observer,
                    parent_pid_poll_interval=0,
                )
            )
            await asyncio.wait_for(task, timeout=1)

            self.assertFalse(socket_path.exists())
            self.assertTrue(self.controller.closed)
            self.assertGreaterEqual(observer.calls, 2)

    async def test_parent_watchdog_records_initial_parent_pid(self):
        observer = FakeParentPidObserver([2222, 2222, 1111])
        await asyncio.wait_for(
            watch_parent_process(
                2222,
                observe_parent_pid=observer,
                poll_interval=0,
            ),
            timeout=1,
        )
        self.assertGreaterEqual(observer.calls, 3)


class SocketPermissionTests(unittest.TestCase):
    def test_socket_parent_is_owner_only(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "nested" / "companion.sock"
            validate_socket_path(path)
            self.assertEqual(path.parent.stat().st_mode & 0o777, 0o700)

    def test_socket_parent_must_already_be_private_when_present(self):
        with tempfile.TemporaryDirectory() as directory:
            parent = Path(directory) / "open-parent"
            parent.mkdir(mode=0o755)
            path = parent / "companion.sock"
            with self.assertRaisesRegex(RuntimeError, "unsafe_socket_parent"):
                validate_socket_path(path)

    def test_helper_uses_memory_storage_only(self):
        source = (Path(__file__).parents[1] / "helper.py").read_text()
        self.assertIn("MemoryStorage", source)
        self.assertNotIn("FileStorage", source)


if __name__ == "__main__":
    unittest.main()

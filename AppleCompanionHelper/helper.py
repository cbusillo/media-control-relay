#!/usr/bin/env python3
"""Optional Apple Companion adapter for Media Control Relay."""

from __future__ import annotations

import argparse
import asyncio
import json
import logging
import os
import secrets
import signal
import stat
from collections.abc import Awaitable, Callable
from pathlib import Path
from typing import Any, Protocol

import pyatv
from pyatv.const import FeatureName, FeatureState, Protocol as PyATVProtocol
from pyatv.storage.memory_storage import MemoryStorage

MAX_FRAME_BYTES = 16 * 1024
CAPABILITY_FEATURES = {
    "navigation": (FeatureName.Up, FeatureName.Down, FeatureName.Left, FeatureName.Right),
    "select": (FeatureName.Select,),
    "back": (FeatureName.Menu,),
    "home": (FeatureName.Home,),
    "playPause": (FeatureName.PlayPause,),
    "previous": (FeatureName.Previous,),
    "next": (FeatureName.Next,),
    "relativeSeek": (FeatureName.SkipForward, FeatureName.SkipBackward),
    "relativeVolume": (FeatureName.VolumeUp, FeatureName.VolumeDown),
}


class Controller(Protocol):
    async def handle(self, operation: dict[str, Any]) -> dict[str, Any]: ...

    async def close(self) -> None: ...


class HelperError(Exception):
    """A bounded, client-visible helper error category."""

    def __init__(self, code: str, state: str = "offline") -> None:
        super().__init__(code)
        self.code = code
        self.state = state


def result(
    state: str,
    *,
    capabilities: list[str] | None = None,
    targets: list[dict[str, str]] | None = None,
    secret: dict[str, str | None] | None = None,
) -> dict[str, Any]:
    return {
        "state": state,
        "capabilities": capabilities or [],
        "targets": targets or [],
        "secret": secret,
    }


class PyATVController:
    def __init__(self) -> None:
        self.storage = MemoryStorage()
        self.targets: dict[str, Any] = {}
        self.pairing: Any = None
        self.pairing_config: Any = None
        self.atv: Any = None

    async def handle(self, operation: dict[str, Any]) -> dict[str, Any]:
        operation_name = operation.get("operation")
        if operation_name == "discover":
            return await self._discover()
        if operation_name == "beginPairing":
            return await self._begin_pairing(operation)
        if operation_name == "finishPairing":
            return await self._finish_pairing(operation)
        if operation_name == "connect":
            return await self._connect(operation)
        if operation_name == "status":
            return self._status()
        if operation_name == "action":
            return await self._action(operation.get("action"))
        if operation_name == "disconnect":
            await self._disconnect()
            return result("dormant")
        raise HelperError("malformedRequest")

    async def close(self) -> None:
        await self._close_pairing()
        await self._disconnect()

    async def _discover(self) -> dict[str, Any]:
        configs = await pyatv.scan(
            asyncio.get_running_loop(),
            protocol=PyATVProtocol.Companion,
            storage=self.storage,
        )
        self.targets.clear()
        targets: list[dict[str, str]] = []
        for config in configs:
            target_id = secrets.token_urlsafe(18)
            self.targets[target_id] = config
            targets.append({"id": target_id, "name": config.name or "Apple TV"})
        targets.sort(key=lambda target: target["name"].casefold())
        return result("dormant", targets=targets)

    async def _begin_pairing(self, operation: dict[str, Any]) -> dict[str, Any]:
        target_id = operation.get("targetID")
        if not isinstance(target_id, str) or not 1 <= len(target_id) <= 128:
            raise HelperError("malformedRequest")
        config = self.targets.get(target_id)
        if config is None:
            raise HelperError("unavailable")

        await self._close_pairing()
        pairing = await pyatv.pair(
            config,
            PyATVProtocol.Companion,
            asyncio.get_running_loop(),
            storage=self.storage,
            name="Media Control Relay",
        )
        try:
            await pairing.begin()
        except Exception as error:
            await pairing.close()
            raise HelperError("pairingFailed") from error
        self.pairing = pairing
        self.pairing_config = config
        return result("pairingRequired")

    async def _finish_pairing(self, operation: dict[str, Any]) -> dict[str, Any]:
        pin = operation.get("pin")
        if not isinstance(pin, int) or not 0 <= pin <= 9999:
            raise HelperError("malformedRequest")
        if self.pairing is None or self.pairing_config is None:
            raise HelperError("pairingRequired", "pairingRequired")

        pairing = self.pairing
        config = self.pairing_config
        try:
            pairing.pin(pin)
            await pairing.finish()
            credential = pairing.service.credentials
        except Exception as error:
            raise HelperError("pairingFailed") from error
        finally:
            await pairing.close()
            self.pairing = None
            self.pairing_config = None

        if not credential or not config.set_credentials(PyATVProtocol.Companion, str(credential)):
            raise HelperError("pairingFailed")
        connection_secret = {
            "host": str(config.address),
            "identifier": config.identifier,
            "credentials": str(credential),
        }
        try:
            await self._connect_config(config)
        except Exception:
            return result("offline", secret=connection_secret)
        return result("ready", capabilities=self._capabilities(), secret=connection_secret)

    async def _connect(self, operation: dict[str, Any]) -> dict[str, Any]:
        secret_value = operation.get("secret")
        if not isinstance(secret_value, dict):
            raise HelperError("malformedRequest")
        host = secret_value.get("host")
        identifier = secret_value.get("identifier")
        credentials = secret_value.get("credentials")
        if (
            not isinstance(host, str)
            or not 1 <= len(host) <= 255
            or (identifier is not None and not isinstance(identifier, str))
            or not isinstance(credentials, str)
            or not 1 <= len(credentials) <= 4096
        ):
            raise HelperError("malformedRequest")

        configs = await pyatv.scan(
            asyncio.get_running_loop(),
            hosts=[host],
            identifier=identifier or None,
            protocol=PyATVProtocol.Companion,
            storage=self.storage,
        )
        if not configs and identifier:
            configs = await pyatv.scan(
                asyncio.get_running_loop(),
                identifier=identifier,
                protocol=PyATVProtocol.Companion,
                storage=self.storage,
            )
        if not configs:
            raise HelperError("offline")
        config = configs[0]
        if not config.set_credentials(PyATVProtocol.Companion, credentials):
            raise HelperError("pairingRequired", "pairingRequired")
        try:
            await self._connect_config(config)
        except Exception as error:
            raise HelperError("offline") from error
        refreshed_secret = {
            "host": str(config.address),
            "identifier": config.identifier,
            "credentials": credentials,
        }
        return result(
            "ready",
            capabilities=self._capabilities(),
            secret=refreshed_secret,
        )

    async def _connect_config(self, config: Any) -> None:
        await self._disconnect()
        self.atv = await pyatv.connect(
            config,
            asyncio.get_running_loop(),
            protocol=PyATVProtocol.Companion,
            storage=self.storage,
        )

    def _status(self) -> dict[str, Any]:
        if self.atv is not None:
            return result("ready", capabilities=self._capabilities())
        if self.pairing is not None:
            return result("pairingRequired")
        return result("dormant")

    def _capabilities(self) -> list[str]:
        if self.atv is None:
            return []
        features = self.atv.features
        return [
            capability
            for capability, feature_names in CAPABILITY_FEATURES.items()
            if all(
                features.get_feature(feature_name).state == FeatureState.Available
                for feature_name in feature_names
            )
        ]

    async def _action(self, action: Any) -> dict[str, Any]:
        if self.atv is None:
            raise HelperError("offline")
        if not isinstance(action, dict) or not isinstance(action.get("action"), str):
            raise HelperError("malformedRequest")
        action_name = action["action"]
        required_capability = {
            "navigate": "navigation",
            "select": "select",
            "back": "back",
            "home": "home",
            "playPause": "playPause",
            "previous": "previous",
            "next": "next",
            "relativeSeek": "relativeSeek",
            "relativeVolume": "relativeVolume",
        }.get(action_name)
        if required_capability and required_capability not in self._capabilities():
            raise HelperError("unsupportedAction", "ready")

        remote = self.atv.remote_control
        if action_name == "navigate":
            commands: dict[str, Callable[[], Awaitable[None]]] = {
                "up": remote.up,
                "down": remote.down,
                "left": remote.left,
                "right": remote.right,
            }
            direction = action.get("direction")
            command = commands.get(direction) if isinstance(direction, str) else None
            if command is None:
                raise HelperError("unsupportedAction", "ready")
            await command()
        elif action_name == "select":
            await remote.select()
        elif action_name == "back":
            await remote.menu()
        elif action_name == "home":
            await remote.home()
        elif action_name == "playPause":
            await remote.play_pause()
        elif action_name == "previous":
            await remote.previous()
        elif action_name == "next":
            await remote.next()
        elif action_name == "relativeSeek":
            await self._skip(remote, action.get("delta"))
        elif action_name == "relativeVolume":
            await self._volume(remote, action.get("delta"))
        else:
            raise HelperError("unsupportedAction", "ready")
        return result("ready", capabilities=self._capabilities())

    async def _skip(self, remote: Any, delta: Any) -> None:
        if not isinstance(delta, int) or delta == 0 or abs(delta) > 60:
            raise HelperError("unsupportedAction", "ready")
        if delta > 0:
            await remote.skip_forward(delta)
        else:
            await remote.skip_backward(abs(delta))

    async def _volume(self, remote: Any, delta: Any) -> None:
        if not isinstance(delta, int) or delta == 0 or abs(delta) > 24:
            raise HelperError("unsupportedAction", "ready")
        command = remote.volume_up if delta > 0 else remote.volume_down
        for _ in range(abs(delta)):
            await command()

    async def _close_pairing(self) -> None:
        if self.pairing is not None:
            await self.pairing.close()
        self.pairing = None
        self.pairing_config = None

    async def _disconnect(self) -> None:
        if self.atv is not None:
            tasks = self.atv.close()
            if tasks:
                await asyncio.gather(*tasks, return_exceptions=True)
        self.atv = None


def validate_socket_path(path: Path) -> None:
    path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    parent_info = os.lstat(path.parent)
    if (
        not stat.S_ISDIR(parent_info.st_mode)
        or parent_info.st_uid != os.getuid()
        or parent_info.st_mode & 0o077
    ):
        raise RuntimeError("unsafe_socket_parent")
    try:
        info = os.lstat(path)
    except FileNotFoundError:
        return
    if not stat.S_ISSOCK(info.st_mode) or info.st_uid != os.getuid() or info.st_mode & 0o077:
        raise RuntimeError("unsafe_socket")
    path.unlink()


async def write_message(writer: asyncio.StreamWriter, message: dict[str, Any]) -> None:
    frame = json.dumps(message, separators=(",", ":"), ensure_ascii=True).encode() + b"\n"
    if len(frame) > MAX_FRAME_BYTES:
        raise HelperError("oversizedFrame")
    writer.write(frame)
    await writer.drain()


def reply(
    request_id: int,
    generation: int,
    operation_result: dict[str, Any],
    error: str | None = None,
) -> dict[str, Any]:
    return {
        "kind": "reply",
        "reply": {
            "id": request_id,
            "generation": generation,
            "state": operation_result["state"],
            "capabilities": operation_result["capabilities"],
            "targets": operation_result["targets"],
            "secret": operation_result["secret"],
            "error": error,
        },
    }


async def serve_client(
    reader: asyncio.StreamReader,
    writer: asyncio.StreamWriter,
    controller: Controller,
) -> None:
    try:
        while True:
            try:
                line = await reader.readuntil(b"\n")
            except (asyncio.IncompleteReadError, asyncio.LimitOverrunError):
                return
            if not line or len(line) > MAX_FRAME_BYTES or not line.endswith(b"\n"):
                return
            request_id = 0
            generation = 0
            try:
                message = json.loads(line)
                if not isinstance(message, dict) or message.get("kind") != "request":
                    raise ValueError
                request = message["request"]
                if not isinstance(request, dict):
                    raise ValueError
                request_id = request["id"]
                generation = request["generation"]
                operation = request["operation"]
                if (
                    not isinstance(request_id, int)
                    or request_id < 0
                    or not isinstance(generation, int)
                    or generation < 0
                    or not isinstance(operation, dict)
                ):
                    raise ValueError
                operation_result = await controller.handle(operation)
                await write_message(writer, reply(request_id, generation, operation_result))
            except HelperError as error:
                await write_message(
                    writer,
                    reply(request_id, generation, result(error.state), error.code),
                )
            except (KeyError, TypeError, ValueError, json.JSONDecodeError):
                return
            except Exception:
                await write_message(
                    writer,
                    reply(request_id, generation, result("offline"), "offline"),
                )
    finally:
        writer.close()
        await writer.wait_closed()


async def serve_exclusive_client(
    reader: asyncio.StreamReader,
    writer: asyncio.StreamWriter,
    controller: Controller,
    client_lock: asyncio.Lock,
) -> None:
    if client_lock.locked():
        writer.close()
        await writer.wait_closed()
        return
    async with client_lock:
        await serve_client(reader, writer, controller)


async def run(socket_path: Path, controller: Controller | None = None) -> None:
    validate_socket_path(socket_path)
    active_controller = controller or PyATVController()
    client_lock = asyncio.Lock()
    previous_umask = os.umask(0o077)
    try:
        server = await asyncio.start_unix_server(
            lambda reader, writer: serve_exclusive_client(
                reader,
                writer,
                active_controller,
                client_lock,
            ),
            path=str(socket_path),
            limit=MAX_FRAME_BYTES + 1,
        )
    finally:
        os.umask(previous_umask)
    os.chmod(socket_path, 0o600)
    try:
        await server.serve_forever()
    except asyncio.CancelledError:
        pass
    finally:
        server.close()
        await server.wait_closed()
        await active_controller.close()
        try:
            socket_path.unlink()
        except FileNotFoundError:
            pass


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.parse_args()
    socket_path = os.environ.get("MEDIA_CONTROL_RELAY_SOCKET")
    if not socket_path:
        parser.error("socket path must be supplied by the app environment")

    logging.disable(logging.CRITICAL)
    loop = asyncio.new_event_loop()
    loop.set_exception_handler(lambda _loop, _context: None)
    asyncio.set_event_loop(loop)
    task = loop.create_task(run(Path(socket_path)))
    for signal_name in (signal.SIGTERM, signal.SIGINT):
        loop.add_signal_handler(signal_name, task.cancel)
    try:
        loop.run_until_complete(task)
    finally:
        loop.close()


if __name__ == "__main__":
    main()

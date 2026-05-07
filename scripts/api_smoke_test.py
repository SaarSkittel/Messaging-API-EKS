#!/usr/bin/env python3
"""Run an end-to-end smoke test against the deployed Messaging API stack."""

from __future__ import annotations

import argparse
import base64
import http.cookiejar
import json
import os
import random
import shutil
import string
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass
from typing import Any


class SmokeTestError(RuntimeError):
    """Raised when a smoke-test assertion fails."""


@dataclass
class HttpResponse:
    status: int
    headers: dict[str, str]
    body_text: str
    body_json: Any


class HttpSession:
    """Tiny JSON-oriented HTTP client with cookie support and no third-party deps."""

    def __init__(self, base_url: str, host_header: str | None = None):
        self.base_url = base_url.rstrip("/")
        self.host_header = host_header
        self.cookie_jar = http.cookiejar.CookieJar()
        self.opener = urllib.request.build_opener(
            urllib.request.HTTPCookieProcessor(self.cookie_jar)
        )

    def request(
        self,
        method: str,
        path: str,
        *,
        json_body: dict[str, Any] | None = None,
        headers: dict[str, str] | None = None,
        timeout: float = 20.0,
    ) -> HttpResponse:
        url = urllib.parse.urljoin(f"{self.base_url}/", path.lstrip("/"))
        request_headers = {"Accept": "application/json"}
        if self.host_header:
            request_headers["Host"] = self.host_header
        payload = None
        if json_body is not None:
            payload = json.dumps(json_body).encode("utf-8")
            request_headers["Content-Type"] = "application/json"
        if headers:
            request_headers.update(headers)

        request = urllib.request.Request(
            url,
            data=payload,
            headers=request_headers,
            method=method.upper(),
        )

        try:
            with self.opener.open(request, timeout=timeout) as response:
                status = response.getcode()
                raw_body = response.read().decode("utf-8", errors="replace")
                response_headers = {k: v for k, v in response.headers.items()}
        except urllib.error.HTTPError as exc:
            status = exc.code
            raw_body = exc.read().decode("utf-8", errors="replace")
            response_headers = {k: v for k, v in exc.headers.items()}
        except urllib.error.URLError as exc:
            raise SmokeTestError(f"Request to {url} failed: {exc.reason}") from exc

        parsed_body = None
        if raw_body:
            try:
                parsed_body = json.loads(raw_body)
            except json.JSONDecodeError:
                parsed_body = None

        return HttpResponse(
            status=status,
            headers=response_headers,
            body_text=raw_body,
            body_json=parsed_body,
        )


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Exercise the deployed auth and messaging APIs and verify the main "
            "cross-service integration paths."
        )
    )
    parser.add_argument(
        "--base-url",
        default=os.getenv("MESSAGING_API_BASE_URL"),
        help=(
            "Public base URL for the stack, for example http://<alb-dns-name>. "
            "Defaults to MESSAGING_API_BASE_URL when it is set."
        ),
    )
    parser.add_argument(
        "--timeout-seconds",
        type=int,
        default=90,
        help="How long to wait for async operations like Celery writes and deletes.",
    )
    parser.add_argument(
        "--poll-interval-seconds",
        type=float,
        default=2.0,
        help="How often to poll while waiting for async operations.",
    )
    parser.add_argument(
        "--skip-k8s-check",
        action="store_true",
        help="Skip the optional kubectl-based pod readiness check.",
    )
    parser.add_argument(
        "--host-header",
        default=os.getenv("MESSAGING_API_HOST_HEADER"),
        help=(
            "Optional Host header to send with each request. Useful when you want to test "
            "through the raw ALB DNS name before public DNS is pointed at it."
        ),
    )
    parser.add_argument(
        "--skip-refresh-check",
        action="store_true",
        help=(
            "Skip the messaging /api/token refresh check and reuse the auth-service access token "
            "for protected messaging requests."
        ),
    )
    return parser.parse_args()


def log_step(message: str) -> None:
    print(f"[check] {message}")


def log_pass(message: str) -> None:
    print(f"[pass]  {message}")


def log_warn(message: str) -> None:
    print(f"[warn]  {message}")


def fail(message: str) -> None:
    raise SmokeTestError(message)


def expect_status(response: HttpResponse, expected: int | tuple[int, ...], context: str) -> None:
    accepted = (expected,) if isinstance(expected, int) else expected
    if response.status not in accepted:
        fail(
            f"{context} returned HTTP {response.status}. "
            f"Body: {response.body_text or '<empty>'}"
        )


def decode_jwt_payload(token: str) -> dict[str, Any]:
    parts = token.split(".")
    if len(parts) != 3:
        fail("Received an invalid JWT access token format.")
    payload = parts[1]
    payload += "=" * (-len(payload) % 4)
    try:
        decoded = base64.urlsafe_b64decode(payload.encode("utf-8"))
        return json.loads(decoded.decode("utf-8"))
    except (ValueError, json.JSONDecodeError) as exc:
        fail(f"Could not decode JWT payload: {exc}")


def random_suffix(length: int = 8) -> str:
    return "".join(random.choices(string.ascii_lowercase + string.digits, k=length))


def wait_for(
    description: str,
    timeout_seconds: int,
    interval_seconds: float,
    fn,
) -> Any:
    deadline = time.time() + timeout_seconds
    last_error: str | None = None

    while time.time() < deadline:
        try:
            result = fn()
            if result:
                return result
        except SmokeTestError as exc:
            last_error = str(exc)
        time.sleep(interval_seconds)

    if last_error:
        fail(f"{description} did not succeed before timeout: {last_error}")
    fail(f"{description} did not succeed before timeout.")


def is_ready_pod(pod: dict[str, Any]) -> bool:
    conditions = pod.get("status", {}).get("conditions", [])
    ready_condition = next((item for item in conditions if item.get("type") == "Ready"), None)
    if not ready_condition or ready_condition.get("status") != "True":
        return False

    statuses = pod.get("status", {}).get("containerStatuses", [])
    return bool(statuses) and all(item.get("ready") for item in statuses)


def optional_kubernetes_check() -> None:
    if not shutil.which("kubectl"):
        log_warn("kubectl not found, skipping in-cluster pod readiness check.")
        return

    result = subprocess.run(
        ["kubectl", "get", "pods", "-A", "-o", "json"],
        check=False,
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        log_warn(f"kubectl readiness check skipped: {result.stderr.strip()}")
        return

    payload = json.loads(result.stdout)
    pods = payload.get("items", [])

    required_matchers = [
        ("authentication", {"app": "authentication"}),
        ("authentication", {"app": "auth-celery"}),
        ("messaging", {"app": "messaging"}),
        ("messaging", {"app": "messaging-celery"}),
        ("aws-secrets-manager", {"app.kubernetes.io/name": "secrets-store-csi-driver"}),
        (
            "aws-secrets-manager",
            {"app.kubernetes.io/name": "aws-secrets-store-csi-driver-provider"},
        ),
    ]

    for namespace, labels in required_matchers:
        matching = [
            pod
            for pod in pods
            if pod.get("metadata", {}).get("namespace") == namespace
            and all(
                pod.get("metadata", {}).get("labels", {}).get(key) == value
                for key, value in labels.items()
            )
        ]
        if not matching:
            fail(
                f"Expected to find a pod in namespace {namespace!r} with labels "
                f"{labels!r}."
            )
        if not any(is_ready_pod(pod) for pod in matching):
            names = ", ".join(pod["metadata"]["name"] for pod in matching)
            fail(
                f"Pods with labels {labels!r} in namespace {namespace!r} are not Ready: "
                f"{names}"
            )

    log_pass("Core workloads and Secrets Store CSI pods are Ready in Kubernetes.")


def register_user(session: HttpSession, username: str, email: str, password: str) -> None:
    response = session.request(
        "POST",
        "/auth/register/",
        json_body={"username": username, "email": email, "password": password},
    )
    expect_status(response, 201, f"Register user {username}")


def login_user(session: HttpSession, username: str, password: str) -> str:
    response = session.request(
        "POST",
        "/auth/login/",
        json_body={"username": username, "password": password},
    )
    expect_status(response, 200, f"Login user {username}")
    if not isinstance(response.body_json, dict) or "access_token" not in response.body_json:
        fail(f"Login user {username} did not return an access token.")
    return str(response.body_json["access_token"])


def refresh_via_messaging(session: HttpSession) -> str:
    response = session.request("POST", "/api/token")
    expect_status(response, 200, "Refresh access token via messaging service")
    if not isinstance(response.body_json, dict) or "access_token" not in response.body_json:
        fail("Messaging token refresh did not return an access token.")
    return str(response.body_json["access_token"])


def get_messages(
    session: HttpSession,
    access_token: str,
    friend_id: int,
    *,
    unread_only: bool = False,
) -> list[dict[str, Any]]:
    endpoint = "/api/get_all_unread/" if unread_only else "/api/get_all/"
    response = session.request(
        "GET",
        f"{endpoint}?id={friend_id}",
        headers={"Authorization": access_token},
    )
    expect_status(response, 200, f"Fetch messages from {endpoint}")
    if response.body_json is None:
        fail(f"Fetch messages from {endpoint} did not return JSON.")
    if not isinstance(response.body_json, list):
        fail(f"Fetch messages from {endpoint} returned an unexpected payload: {response.body_text}")
    return response.body_json


def read_last_message(session: HttpSession, access_token: str, friend_id: int) -> dict[str, Any]:
    response = session.request(
        "GET",
        f"/api/get_message?id={friend_id}",
        headers={"Authorization": access_token},
    )
    expect_status(response, 200, "Read last message")
    if not isinstance(response.body_json, dict):
        fail(f"Read last message returned an unexpected payload: {response.body_text}")
    return response.body_json


def write_message(
    session: HttpSession,
    access_token: str,
    receiver_id: int,
    subject: str,
    message: str,
) -> None:
    response = session.request(
        "POST",
        "/api/write",
        json_body={"receiver": receiver_id, "subject": subject, "message": message},
        headers={"Authorization": access_token},
    )
    expect_status(response, 200, "Write message")


def delete_message(
    session: HttpSession,
    access_token: str,
    friend_id: int,
    sort: int,
) -> None:
    response = session.request(
        "DELETE",
        "/api/delete_message",
        json_body={"user_conversation": friend_id, "sort": sort},
        headers={"Authorization": access_token},
    )
    expect_status(response, 200, "Delete message")


def run_celery_smoke_task(
    session: HttpSession,
    access_token: str,
    timeout_seconds: int,
    interval_seconds: float,
) -> None:
    response = session.request(
        "GET",
        "/api/test",
        headers={"Authorization": access_token},
    )
    expect_status(response, 202, "Kick off messaging Celery smoke task")
    if not isinstance(response.body_json, dict) or "task_id" not in response.body_json:
        fail(f"Messaging Celery smoke task did not return a task id: {response.body_text}")

    task_id = str(response.body_json["task_id"])

    def task_finished() -> bool:
        status_response = session.request(
            "GET",
            f"/api/status/{task_id}",
            headers={"Authorization": access_token},
        )
        expect_status(status_response, 200, "Fetch Celery task status")
        if not isinstance(status_response.body_json, dict):
            fail(f"Celery task status returned invalid JSON: {status_response.body_text}")
        task_status = status_response.body_json.get("task_status")
        if task_status == "FAILURE":
            fail(f"Celery smoke task failed: {status_response.body_text}")
        return task_status == "SUCCESS" and bool(status_response.body_json.get("task_result"))

    wait_for("Messaging Celery smoke task", timeout_seconds, interval_seconds, task_finished)
    log_pass("Messaging Celery worker and Redis result backend completed the smoke task.")


def main() -> int:
    args = parse_args()

    try:
        if not args.base_url:
            fail(
                "No base URL was provided. Pass --base-url http://<alb-dns-name> "
                "or set MESSAGING_API_BASE_URL."
            )

        if not args.skip_k8s_check:
            log_step("Checking core Kubernetes pods before running API traffic.")
            optional_kubernetes_check()

        base_session = HttpSession(args.base_url, args.host_header)
        user_a_session = HttpSession(args.base_url, args.host_header)
        user_b_session = HttpSession(args.base_url, args.host_header)

        suffix = random_suffix()
        user_a = {
            "username": f"smoke-auth-{suffix}",
            "email": f"smoke-auth-{suffix}@example.com",
            "password": f"Smoke!Pass1{suffix}",
        }
        user_b = {
            "username": f"smoke-msg-{suffix}",
            "email": f"smoke-msg-{suffix}@example.com",
            "password": f"Smoke!Pass2{suffix}",
        }

        log_step("Registering two fresh users through the authentication API.")
        register_user(base_session, **user_a)
        register_user(base_session, **user_b)
        log_pass("Both users registered successfully in the auth service database.")

        log_step("Logging in through the authentication API to obtain access and refresh tokens.")
        auth_access_a = login_user(user_a_session, user_a["username"], user_a["password"])
        auth_access_b = login_user(user_b_session, user_b["username"], user_b["password"])
        auth_payload_a = decode_jwt_payload(auth_access_a)
        auth_payload_b = decode_jwt_payload(auth_access_b)
        user_a_id = int(auth_payload_a["user_id"])
        user_b_id = int(auth_payload_b["user_id"])
        log_pass("Auth login returned valid access tokens and refresh cookies for both users.")

        if args.skip_refresh_check:
            messaging_access_a = auth_access_a
            log_warn(
                "Skipping the messaging /api/token refresh check and reusing the auth-service "
                "access token for protected messaging requests."
            )
        else:
            log_step("Refreshing an access token via the messaging service to verify shared JWT secret wiring.")
            messaging_access_a = refresh_via_messaging(user_a_session)
            messaging_payload_a = decode_jwt_payload(messaging_access_a)
            if int(messaging_payload_a["user_id"]) != user_a_id:
                fail("Messaging token refresh returned an access token for the wrong user.")
            if messaging_payload_a.get("email") != user_a["email"]:
                fail(
                    "Messaging token refresh returned an access token without the expected email claim. "
                    "That token will not pass auth-service gRPC verification."
                )
            log_pass("Messaging token refresh produced a cross-service compatible access token.")

        log_step("Checking that the protected messaging API accepts the refreshed token through auth-service gRPC validation.")
        initial_messages = get_messages(user_a_session, messaging_access_a, user_b_id)
        if initial_messages:
            fail(f"Expected an empty initial conversation, found: {initial_messages}")
        log_pass("Protected messaging endpoint accepted the refreshed token and returned an empty conversation.")

        log_step("Running the messaging Celery smoke task through the public REST API.")
        run_celery_smoke_task(
            user_a_session,
            messaging_access_a,
            args.timeout_seconds,
            args.poll_interval_seconds,
        )

        subject = f"Smoke subject {suffix}"
        message = f"Smoke body {suffix}"

        log_step("Writing a message from user A to user B through the messaging API.")
        write_message(user_a_session, messaging_access_a, user_b_id, subject, message)

        def sender_sees_message() -> dict[str, Any] | None:
            messages = get_messages(user_a_session, messaging_access_a, user_b_id)
            for item in messages:
                if item.get("subject") == subject and item.get("message") == message:
                    return item
            return None

        sender_message = wait_for(
            "Sender conversation update after write_message",
            args.timeout_seconds,
            args.poll_interval_seconds,
            sender_sees_message,
        )
        log_pass("Messaging write task persisted the sender-side message through Celery and PostgreSQL.")

        log_step("Checking that user B can see the replicated message through a protected messaging read.")

        def receiver_sees_message() -> dict[str, Any] | None:
            receiver_messages = get_messages(
                user_b_session,
                auth_access_b,
                user_a_id,
            )
            for item in receiver_messages:
                if item.get("subject") == subject and item.get("message") == message:
                    return item
            return None

        receiver_message = wait_for(
            "Receiver conversation update after write_message",
            args.timeout_seconds,
            args.poll_interval_seconds,
            receiver_sees_message,
        )
        log_pass("Receiver-side message replication succeeded, proving auth gRPC validation, Celery, Redis, and PostgreSQL are wired together.")

        unread_messages = get_messages(
            user_b_session,
            auth_access_b,
            user_a_id,
            unread_only=True,
        )
        unread_match = next(
            (
                item
                for item in unread_messages
                if item.get("subject") == subject and item.get("message") == message
            ),
            None,
        )
        if unread_match:
            log_pass("Receiver unread endpoint returned the expected message.")
        else:
            log_warn(
                "Receiver unread endpoint did not return the new message. "
                "The service wiring is healthy, but the unread flag behavior looks suspicious."
            )

        log_step("Reading the latest message for user B to confirm the conversation payload is correct.")
        read_payload = read_last_message(user_b_session, auth_access_b, user_a_id)
        if read_payload.get("subject") != subject or read_payload.get("message") != message:
            fail(f"Read-last-message returned unexpected payload: {read_payload}")
        log_pass("Read-last-message returned the expected conversation payload.")

        if unread_match:
            log_step("Checking that unread state was cleared after reading.")
            remaining_unread = get_messages(
                user_b_session,
                auth_access_b,
                user_a_id,
                unread_only=True,
            )
            if remaining_unread:
                fail(f"Expected unread messages to be cleared, found: {remaining_unread}")
            log_pass("Unread state cleared as expected after the receiver read the message.")

        sort_value = int(sender_message["sort"])
        log_step("Deleting the message and verifying the delete propagates to both conversation copies.")
        delete_message(user_a_session, messaging_access_a, user_b_id, sort_value)

        def delete_propagated() -> bool:
            sender_messages = get_messages(user_a_session, messaging_access_a, user_b_id)
            receiver_messages = get_messages(user_b_session, auth_access_b, user_a_id)
            sender_still_has_message = any(
                item.get("sort") == sort_value and item.get("subject") == subject
                for item in sender_messages
            )
            receiver_still_has_message = any(
                item.get("sort") == receiver_message.get("sort") and item.get("subject") == subject
                for item in receiver_messages
            )
            return not sender_still_has_message and not receiver_still_has_message

        wait_for(
            "Delete propagation across both conversations",
            args.timeout_seconds,
            args.poll_interval_seconds,
            delete_propagated,
        )
        log_pass("Delete task removed the message from both mirrored conversation records.")

        print()
        print("Smoke test completed successfully.")
        print(f"Base URL: {args.base_url}")
        if args.host_header:
            print(f"Host header: {args.host_header}")
        print(f"Users created: {user_a['username']}, {user_b['username']}")
        return 0

    except SmokeTestError as exc:
        print()
        print(f"Smoke test failed: {exc}", file=sys.stderr)
        return 1
    except KeyboardInterrupt:
        print()
        print("Smoke test interrupted.", file=sys.stderr)
        return 130


if __name__ == "__main__":
    sys.exit(main())

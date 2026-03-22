#!/usr/bin/env python3

from __future__ import annotations

import argparse
import os
import re
import shlex
import shutil
import subprocess
import sys
from pathlib import Path


ROOT_DIR = Path(__file__).resolve().parents[1]
FLUTTER_DIR = ROOT_DIR / "flutter_app"
ANDROID_LOCAL_PROPERTIES = FLUTTER_DIR / "android" / "local.properties"
PUBSPEC_FILE = FLUTTER_DIR / "pubspec.yaml"
RELEASE_ROOT = ROOT_DIR / "release"
DOCS_DIR = ROOT_DIR / "docs"
FETCH_PROOT_SCRIPT = ROOT_DIR / "scripts" / "fetch-proot-binaries.sh"

ABI_ARTIFACTS = {
    "arm64-v8a": "app-arm64-v8a-release.apk",
    "armeabi-v7a": "app-armeabi-v7a-release.apk",
    "x86_64": "app-x86_64-release.apk",
}

COMMAND_CACHE: dict[str, str] = {}


def configure_stdio() -> None:
    for stream_name in ("stdout", "stderr"):
        stream = getattr(sys, stream_name, None)
        if stream and hasattr(stream, "reconfigure"):
            try:
                stream.reconfigure(encoding="utf-8")
            except Exception:
                pass


def read_pubspec_version() -> tuple[str, str]:
    content = PUBSPEC_FILE.read_text(encoding="utf-8")
    match = re.search(r"^version:\s*([^+\s]+)(?:\+(\d+))?", content, re.MULTILINE)
    if not match:
        raise RuntimeError(f"无法从 {PUBSPEC_FILE} 读取版本号")
    version = match.group(1)
    build_number = match.group(2) or "1"
    return version, build_number


def next_build_number(value: str) -> str:
    try:
        return str(int(value) + 1)
    except ValueError:
        return value


def normalize_version(value: str) -> str:
    return value.strip().lstrip("vV")


def ask(prompt: str, default: str, non_interactive: bool) -> str:
    if non_interactive:
        return default
    suffix = f" [{default}]" if default else ""
    answer = input(f"{prompt}{suffix}: ").strip()
    return answer or default


def _git_bash_candidates() -> list[str]:
    candidates: list[str] = []
    for env_key in ("ProgramFiles", "ProgramFiles(x86)", "LocalAppData"):
        base = os.environ.get(env_key)
        if not base:
            continue
        candidates.extend(
            [
                str(Path(base) / "Git" / "bin" / "bash.exe"),
                str(Path(base) / "Git" / "usr" / "bin" / "bash.exe"),
            ]
        )
    return candidates


def _read_local_properties(file_path: Path) -> dict[str, str]:
    if not file_path.exists():
        return {}

    properties: dict[str, str] = {}
    for raw_line in file_path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        properties[key.strip()] = value.strip()
    return properties


def _unescape_properties_value(value: str) -> str:
    return (
        value.replace("\\\\", "\\")
        .replace("\\:", ":")
        .replace("\\=", "=")
        .replace("\\ ", " ")
    )


def _flutter_sdk_candidates() -> list[str]:
    sdk_roots: list[Path] = []

    for env_key in ("FLUTTER_ROOT", "FLUTTER_HOME"):
        value = os.environ.get(env_key)
        if value:
            sdk_roots.append(Path(value).expanduser())

    flutter_sdk = _read_local_properties(ANDROID_LOCAL_PROPERTIES).get("flutter.sdk")
    if flutter_sdk:
        sdk_roots.append(Path(_unescape_properties_value(flutter_sdk)).expanduser())

    executable_names = (
        ("flutter.bat", "flutter.cmd", "flutter.exe", "flutter")
        if os.name == "nt"
        else ("flutter",)
    )

    candidates: list[str] = []
    seen: set[str] = set()
    for sdk_root in sdk_roots:
        for executable_name in executable_names:
            candidate = (sdk_root / "bin" / executable_name).resolve()
            candidate_str = str(candidate)
            if candidate_str in seen:
                continue
            seen.add(candidate_str)
            candidates.append(candidate_str)
    return candidates


def resolve_command(command: str) -> str:
    cached = COMMAND_CACHE.get(command)
    if cached:
        return cached

    candidates: list[str]
    if os.name == "nt" and command == "flutter":
        candidates = _flutter_sdk_candidates() + [
            "flutter.bat",
            "flutter.cmd",
            "flutter.exe",
            "flutter",
        ]
    elif os.name == "nt" and command == "bash":
        candidates = _git_bash_candidates() + ["bash.exe", "bash"]
    else:
        candidates = [command]

    for candidate in candidates:
        resolved = candidate if Path(candidate).exists() else shutil.which(candidate)
        if resolved:
            COMMAND_CACHE[command] = resolved
            return resolved

    if command == "flutter":
        raise RuntimeError(
            "未找到 Flutter 命令。请确认已安装 Flutter，并把 flutter/bin 加入 PATH。"
        )
    if command == "bash":
        raise RuntimeError(
            "未找到可用的 bash。Windows 下建议安装 Git for Windows，并确保 git bash 可用。"
        )
    raise RuntimeError(f"未找到命令：{command}。请先安装并配置到 PATH。")


def ensure_command(command: str) -> None:
    resolve_command(command)


def prepare_command(command: list[str]) -> list[str]:
    executable = resolve_command(command[0])
    final_command = [executable, *command[1:]]

    if os.name == "nt" and Path(executable).suffix.lower() in {".bat", ".cmd"}:
        comspec = os.environ.get("COMSPEC", "cmd.exe")
        return [comspec, "/c", executable, *command[1:]]

    return final_command


def run_command(command: list[str], cwd: Path | None = None) -> None:
    prepared = prepare_command(command)
    command_text = " ".join(shlex.quote(part) for part in prepared)
    print(f"\n>>> {command_text}")
    subprocess.run(prepared, cwd=str(cwd or ROOT_DIR), check=True, env=os.environ.copy())


def need_fetch_proot() -> bool:
    jni_lib_root = FLUTTER_DIR / "android" / "app" / "src" / "main" / "jniLibs"
    required_files = [
        jni_lib_root / "arm64-v8a" / "libproot.so",
        jni_lib_root / "arm64-v8a" / "libprootloader.so",
        jni_lib_root / "armeabi-v7a" / "libproot.so",
        jni_lib_root / "x86_64" / "libproot.so",
    ]
    return any(not file.exists() for file in required_files)


def fetch_proot_if_needed(skip_fetch_proot: bool) -> None:
    if skip_fetch_proot:
        print("[跳过] 已按参数要求跳过 PRoot 二进制检查。")
        return

    if not need_fetch_proot():
        print("[检查] PRoot 二进制已存在，跳过下载。")
        return

    ensure_command("bash")
    print("[步骤 1/4] 检测到缺少 PRoot 二进制，开始拉取……")
    run_command(["bash", str(FETCH_PROOT_SCRIPT)], cwd=ROOT_DIR)


def run_pub_get(skip_pub_get: bool) -> None:
    if skip_pub_get:
        print("[跳过] 已按参数要求跳过 flutter pub get。")
        return

    print("[步骤 2/4] 获取 Flutter 依赖……")
    run_command(["flutter", "pub", "get"], cwd=FLUTTER_DIR)


def build_artifacts(version: str, build_number: str, skip_split: bool, skip_aab: bool) -> None:
    build_args = ["--build-name", version, "--build-number", build_number]

    print("[步骤 3/4] 构建通用 APK……")
    run_command(["flutter", "build", "apk", "--release", *build_args], cwd=FLUTTER_DIR)

    if not skip_split:
        print("[步骤 3/4] 构建分 ABI APK……")
        run_command(
            ["flutter", "build", "apk", "--release", "--split-per-abi", *build_args],
            cwd=FLUTTER_DIR,
        )
    else:
        print("[跳过] 已按参数要求跳过分 ABI APK 构建。")

    if not skip_aab:
        print("[步骤 3/4] 构建 AAB……")
        run_command(["flutter", "build", "appbundle", "--release", *build_args], cwd=FLUTTER_DIR)
    else:
        print("[跳过] 已按参数要求跳过 AAB 构建。")




def copy_if_exists(source: Path, target: Path, copied_files: list[Path]) -> None:
    if not source.exists():
        return
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, target)
    copied_files.append(target)


def collect_artifacts(version: str, output_dir: Path, skip_split: bool, skip_aab: bool) -> list[Path]:
    copied_files: list[Path] = []
    output_dir.mkdir(parents=True, exist_ok=True)

    apk_root = FLUTTER_DIR / "build" / "app" / "outputs" / "flutter-apk"
    bundle_root = FLUTTER_DIR / "build" / "app" / "outputs" / "bundle" / "release"

    universal_source = apk_root / "app-release.apk"
    universal_target = output_dir / f"OpenClaw-v{version}-universal.apk"
    copy_if_exists(universal_source, universal_target, copied_files)

    if not skip_split:
        for abi, file_name in ABI_ARTIFACTS.items():
            source = apk_root / file_name
            target = output_dir / f"OpenClaw-v{version}-{abi}.apk"
            copy_if_exists(source, target, copied_files)

    if not skip_aab:
        aab_source = bundle_root / "app-release.aab"
        aab_target = output_dir / f"OpenClaw-v{version}.aab"
        copy_if_exists(aab_source, aab_target, copied_files)

    doc_source = DOCS_DIR / f"release-v{version}.zh.md"
    doc_target = output_dir / "Release.zh.md"
    if doc_source.exists() and not doc_target.exists():
        shutil.copy2(doc_source, doc_target)
        copied_files.append(doc_target)

    return copied_files


def print_summary(version: str, build_number: str, output_dir: Path, copied_files: list[Path]) -> None:
    print("\n[步骤 4/4] 构建完成，产物整理如下：")
    print(f"版本号: {version}")
    print(f"构建号: {build_number}")
    print(f"输出目录: {output_dir}")

    if not copied_files:
        raise RuntimeError("构建命令已执行，但未在输出目录中整理到任何产物。请检查 Flutter 构建日志。")

    for file in copied_files:
        size_mb = file.stat().st_size / 1024 / 1024
        print(f"- {file.name}  ({size_mb:.2f} MB)")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="构建 OpenClaw Android 发布产物，并整理到 release/v版本 目录。")
    parser.add_argument("--version", help="发布版本号，例如 1.8.7 或 v1.8.7；默认使用当前 pubspec 版本")
    parser.add_argument("--build-number", help="Android 构建号，例如 17；默认使用当前 pubspec 构建号 +1")
    parser.add_argument("--output-dir", help="自定义输出目录，默认是 release/v版本")
    parser.add_argument("--non-interactive", action="store_true", help="不询问输入，直接使用参数或默认值")
    parser.add_argument("--skip-fetch-proot", action="store_true", help="跳过 PRoot 二进制检查与拉取")
    parser.add_argument("--skip-pub-get", action="store_true", help="跳过 flutter pub get")
    parser.add_argument("--skip-split-apk", action="store_true", help="跳过分 ABI APK 构建")
    parser.add_argument("--skip-aab", action="store_true", help="跳过 AAB 构建")
    return parser.parse_args()


def main() -> int:
    configure_stdio()
    args = parse_args()

    pubspec_version, pubspec_build_number = read_pubspec_version()
    default_version = normalize_version(pubspec_version)
    default_build_number = next_build_number(pubspec_build_number)

    current_version_text = f"{pubspec_version}+{pubspec_build_number}"

    version = normalize_version(
        args.version
        or ask(
            f"请输入发布版本（当前 pubspec: {current_version_text}）",
            default_version,
            args.non_interactive,
        )
    )
    build_number = args.build_number or ask(
        f"请输入构建号（当前 pubspec 构建号: {pubspec_build_number}，默认自动 +1）",
        default_build_number,
        args.non_interactive,
    )

    if not version:
        raise RuntimeError("发布版本不能为空。")
    if not build_number.isdigit():
        raise RuntimeError("构建号必须是整数。")

    output_dir = Path(args.output_dir).expanduser().resolve() if args.output_dir else (RELEASE_ROOT / f"v{version}").resolve()

    print("=" * 60)
    print("OpenClaw 发布构建脚本")
    print(f"项目目录: {ROOT_DIR}")
    print(f"Flutter 目录: {FLUTTER_DIR}")
    print(f"当前 pubspec: {current_version_text}")
    print(f"发布版本: {version}")
    print(f"构建号: {build_number}")
    print(f"输出目录: {output_dir}")
    print("=" * 60)

    ensure_command("flutter")

    fetch_proot_if_needed(args.skip_fetch_proot)
    run_pub_get(args.skip_pub_get)
    build_artifacts(version, build_number, args.skip_split_apk, args.skip_aab)
    copied_files = collect_artifacts(version, output_dir, args.skip_split_apk, args.skip_aab)
    print_summary(version, build_number, output_dir, copied_files)

    print("\n提示：如果你要正式发布，建议使用自己的 keystore 进行签名。")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except subprocess.CalledProcessError as error:
        print(f"\n构建失败：命令返回非 0 状态码 {error.returncode}")
        raise SystemExit(error.returncode)
    except KeyboardInterrupt:
        print("\n已取消构建。")
        raise SystemExit(130)
    except Exception as error:
        print(f"\n构建失败：{error}")
        raise SystemExit(1)

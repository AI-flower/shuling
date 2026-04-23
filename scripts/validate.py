#!/usr/bin/env python3
"""schema drift 校验器 — v2.4.0

把 schemas/ 下 4 份 JSON Schema 对准 runtime 目录下对应文件做校验。
默认人类可读输出；--json 机器可读；退出码给 CI/preflight 用。

用法：
  python3 scripts/validate.py
      校验当前 skill 目录（SKILL_DIR 自动 = 脚本上一级）

  python3 scripts/validate.py --target /path/to/skill
      校验指定 target（如 ~/.codex/skills/shuling）

  python3 scripts/validate.py --file foo.json --schema state
      只校一对

  python3 scripts/validate.py --json
      机器可读 JSON，供 preflight / CI 消费

退出码：
  0  全部 valid
  1  有 drift
  2  schema 或文件读不到（环境问题）
"""
from __future__ import annotations

import argparse
import glob
import json
import sys
from pathlib import Path


SCHEMA_TARGETS = [
    # (schema 名, schema 文件, 相对 target 的 runtime 路径模式, 是否 glob)
    # 文件缺失不当 drift 处理——这些是 skill 运行期才生成的业务状态，
    # 归 preflight 识别；validate.py 只关心"文件存在但违反 schema"。
    ("state",         "state.schema.json",         "config/state.json",               False),
    ("profile",       "profile.schema.json",       "knowledge-base/profile.json",     False),
    ("preferences",   "preferences.schema.json",   "knowledge-base/preferences.json", False),
    ("audit-report",  "audit-report.schema.json",  "knowledge-base/audit-*.json",     True),
]


def _default_skill_dir() -> Path:
    return Path(__file__).resolve().parent.parent


def _load_json(path: Path) -> tuple[dict | None, str | None]:
    try:
        return json.loads(path.read_text(encoding="utf-8")), None
    except FileNotFoundError:
        return None, f"file not found: {path}"
    except json.JSONDecodeError as e:
        return None, f"invalid JSON: {e.msg} (line {e.lineno} col {e.colno})"
    except OSError as e:
        return None, f"read error: {e}"


def _validator_for(schema: dict):
    """按 schema 声明的 $schema 选 Draft validator；默认 2020-12。"""
    try:
        from jsonschema import Draft202012Validator, Draft7Validator, Draft6Validator, Draft4Validator
    except ImportError:
        return None, "jsonschema library not installed; run: pip install -r requirements.txt"

    decl = (schema.get("$schema") or "").rstrip("#")
    table = {
        "https://json-schema.org/draft/2020-12/schema": Draft202012Validator,
        "http://json-schema.org/draft-07/schema": Draft7Validator,
        "http://json-schema.org/draft-06/schema": Draft6Validator,
        "http://json-schema.org/draft-04/schema": Draft4Validator,
    }
    validator_cls = table.get(decl, Draft202012Validator)
    return validator_cls(schema), None


def _fmt_error(err) -> str:
    """把 jsonschema ValidationError 浓缩成一行。"""
    path = "/".join(str(p) for p in err.absolute_path) or "<root>"
    msg = err.message
    if err.validator == "required":
        return f"missing required field at {path}: {msg}"
    return f"at {path}: {msg}"


def _validate_one(data, schema, schema_name: str, file_path: Path) -> list[dict]:
    validator, err = _validator_for(schema)
    if validator is None:
        return [{"file": str(file_path), "schema": schema_name, "errors": [err], "fatal": True}]
    raw_errors = sorted(validator.iter_errors(data), key=lambda e: list(e.absolute_path))
    if not raw_errors:
        return []
    return [{
        "file": str(file_path),
        "schema": schema_name,
        "errors": [_fmt_error(e) for e in raw_errors],
    }]


def run(target: Path, skill_dir: Path,
        only_file: Path | None = None,
        only_schema: str | None = None) -> dict:
    """返回 dict: {target, valid, drift: [...], fatal: bool}"""
    schemas_dir = skill_dir / "schemas"
    if not schemas_dir.is_dir():
        return {
            "target": str(target),
            "valid": False,
            "drift": [],
            "fatal": True,
            "fatal_reason": f"schemas dir not found: {schemas_dir}",
        }

    drift: list[dict] = []
    fatal = False

    pairs = SCHEMA_TARGETS
    if only_schema:
        pairs = [p for p in pairs if p[0] == only_schema]
        if not pairs:
            return {
                "target": str(target),
                "valid": False,
                "drift": [],
                "fatal": True,
                "fatal_reason": f"unknown schema: {only_schema} (valid: {', '.join(p[0] for p in SCHEMA_TARGETS)})",
            }

    for name, schema_file, rel, is_glob in pairs:
        schema_path = schemas_dir / schema_file
        schema, err = _load_json(schema_path)
        if schema is None:
            drift.append({"file": str(schema_path), "schema": name, "errors": [err], "fatal": True})
            fatal = True
            continue

        if only_file is not None:
            files = [only_file]
        elif is_glob:
            files = [Path(p) for p in sorted(glob.glob(str(target / rel)))]
        else:
            f = target / rel
            files = [f] if f.exists() else []

        for f in files:
            data, err = _load_json(f)
            if data is None:
                drift.append({"file": str(f), "schema": name, "errors": [err]})
                continue
            drift.extend(_validate_one(data, schema, name, f))

    valid = (len(drift) == 0)
    return {
        "target": str(target),
        "valid": valid,
        "drift": drift,
        "fatal": fatal,
    }


def _print_human(result: dict, use_color: bool = True) -> None:
    def c(s, code): return f"\033[{code}m{s}\033[0m" if use_color else s
    target = result["target"]
    if result.get("fatal") and result.get("fatal_reason"):
        print(c(f"✗ {target} — {result['fatal_reason']}", "31"))
        return

    if result["valid"]:
        print(c(f"✓ {target} — all schemas valid", "32"))
        return

    # 按 file 聚合
    by_file: dict[str, dict] = {}
    for item in result["drift"]:
        key = item["file"]
        by_file.setdefault(key, {"schema": item["schema"], "errors": [], "fatal": item.get("fatal", False)})
        by_file[key]["errors"].extend(item["errors"])

    for f, info in by_file.items():
        n = len(info["errors"])
        tag = "schema error" if info.get("fatal") else f"{n} error{'s' if n != 1 else ''}"
        print(c(f"✗ {f} — {tag}", "31"))
        for msg in info["errors"]:
            print(f"  · {msg}")


def _exit_code(result: dict) -> int:
    if result.get("fatal"):
        return 2
    if not result["valid"]:
        return 1
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(
        description="薯灵 schema drift 校验",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument("--target", type=Path,
                        help="要校验的 skill 根目录（默认为本仓库）")
    parser.add_argument("--file", type=Path,
                        help="只校验单个文件（需配 --schema）")
    parser.add_argument("--schema",
                        choices=[p[0] for p in SCHEMA_TARGETS],
                        help="指定使用哪个 schema 校验")
    parser.add_argument("--json", dest="json_only", action="store_true",
                        help="输出机器可读 JSON")
    parser.add_argument("--no-color", action="store_true", help="关闭 ANSI 颜色")
    args = parser.parse_args()

    skill_dir = _default_skill_dir()
    target = args.target.resolve() if args.target else skill_dir
    if args.file and not args.schema:
        print("error: --file 必须配 --schema", file=sys.stderr)
        return 2

    result = run(
        target=target,
        skill_dir=skill_dir,
        only_file=args.file.resolve() if args.file else None,
        only_schema=args.schema,
    )

    if args.json_only:
        print(json.dumps(result, ensure_ascii=False, indent=2))
    else:
        use_color = (not args.no_color) and sys.stdout.isatty()
        _print_human(result, use_color=use_color)

    return _exit_code(result)


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env python3
"""Apply patches to jasl/vllm for REAP K160 on ROCm gfx1030.

Sources:
  - Router patch: 0xSero/deepseek-spark runtime/scripts/patch_vllm_reap_gb10.py
  - EMULATION fallback: discovered at runtime (AITER/TRITON_UNFUSED both gate on
    newer AMD hardware; EMULATION is pure-Triton, no hardware gate)
  - PYTHONPATH note: editable-install finder breaks in this build config;
    set PYTHONPATH=/workspace/vllm at runtime (see runner script)
"""

from pathlib import Path
import py_compile, sys

VLLM_SRC = Path("/workspace/vllm")

# ── Patch 1: REAP K160 router fallback ────────────────────────────────────────
# The fused sqrtsoftplus CUDA top-k kernel only exists for expert counts
# {16,32,64,128,192,256,320,384,512}. REAP K160 uses 160 — route to pure-Torch.

ROUTER_FILE = VLLM_SRC / "vllm/model_executor/layers/fused_moe/router/fused_topk_bias_router.py"

SUPPORTED = "(16, 32, 64, 128, 192, 256, 320, 384, 512)"

ROUTER_OLD = "    if not rocm_aiter_ops.is_fused_moe_enabled():"

ROUTER_NEW = (
    "    # REAP DeepSeek-V4 checkpoints prune to nonstandard routed-expert\n"
    "    # counts (e.g. 160, 144). The fused sqrtsoftplus CUDA top-k kernel\n"
    "    # is only instantiated for a fixed set; route others to pure-Torch.\n"
    "    if not rocm_aiter_ops.is_fused_moe_enabled() and not (\n"
    '        scoring_func == "sqrtsoftplus"\n'
    f"        and gating_output.shape[-1] not in {SUPPORTED}\n"
    "    ):"
)

# ── Patch 2: EMULATION fallback for MXFP4 MoE on gfx1030 ─────────────────────
# For ROCm + DeepseekV4 routing, vLLM auto-selects AITER_MXFP4_BF16 then
# TRITON_UNFUSED. Both gate on newer AMD hardware and reject gfx1030 (RDNA2).
# EMULATION is pure Triton with no hardware gate — slower but correct.

MXFP4_ORACLE_FILE = VLLM_SRC / "vllm/model_executor/layers/fused_moe/oracle/mxfp4.py"

MXFP4_ORACLE_OLD = (
    "        priority_backends = [\n"
    "            Mxfp4MoeBackend.AITER_MXFP4_BF16,\n"
    "            Mxfp4MoeBackend.TRITON_UNFUSED,\n"
    "        ]"
)

MXFP4_ORACLE_NEW = (
    "        priority_backends = [\n"
    "            Mxfp4MoeBackend.AITER_MXFP4_BF16,\n"
    "            Mxfp4MoeBackend.TRITON_UNFUSED,\n"
    "            Mxfp4MoeBackend.EMULATION,  # gfx1030 fallback\n"
    "        ]"
)


# ── Patch 3: EMULATION passthrough in convert_weight_to_mxfp4_moe_kernel_format
# The weights-loaded path hits a second backend switch that didn't include
# EMULATION. XPU and EMULATION both need the same no-op passthrough.

MXFP4_CONVERT_OLD = (
    "    elif mxfp4_backend == Mxfp4MoeBackend.XPU:\n"
    "        # No additional transformation needed for XPU backend\n"
    "        return (\n"
    "            w13_weight,\n"
    "            w2_weight,\n"
    "            w13_weight_scale,\n"
    "            w2_weight_scale,\n"
    "            w13_bias,\n"
    "            w2_bias,\n"
    "        )\n"
    "    else:\n"
    "        raise ValueError(\n"
    '            f"Unsupported mxfp4_backend for Mxfp4MoEMethod: {mxfp4_backend}. "\n'
    '            f"Expected TRTLLM, Triton, AITER, or XPU backend."\n'
    "        )"
)

MXFP4_CONVERT_NEW = (
    "    elif mxfp4_backend == Mxfp4MoeBackend.XPU:\n"
    "        # No additional transformation needed for XPU backend\n"
    "        return (\n"
    "            w13_weight,\n"
    "            w2_weight,\n"
    "            w13_weight_scale,\n"
    "            w2_weight_scale,\n"
    "            w13_bias,\n"
    "            w2_bias,\n"
    "        )\n"
    "    elif mxfp4_backend == Mxfp4MoeBackend.EMULATION:\n"
    "        # No transformation needed; weights dequantized on the fly in kernel\n"
    "        return (\n"
    "            w13_weight,\n"
    "            w2_weight,\n"
    "            w13_weight_scale,\n"
    "            w2_weight_scale,\n"
    "            w13_bias,\n"
    "            w2_bias,\n"
    "        )\n"
    "    else:\n"
    "        raise ValueError(\n"
    '            f"Unsupported mxfp4_backend for Mxfp4MoEMethod: {mxfp4_backend}. "\n'
    '            f"Expected TRTLLM, Triton, AITER, XPU, or EMULATION backend."\n'
    "        )"
)


# ── Patch 4: Disable TileLang MHC kernels on gfx1030 ─────────────────────────
# TileLang JIT-compiles via rocWMMA which static_asserts on unsupported arch.
# gfx1030 (RDNA2) is not supported by rocWMMA. Force forward_native fallback.

MHC_FILE = VLLM_SRC / "vllm/model_executor/layers/mhc.py"
MHC_OLD = "HAS_TILELANG = has_tilelang()"
MHC_NEW = "HAS_TILELANG = False  # gfx1030 (RDNA2) does not support rocWMMA required by TileLang"

# ── Patch 5: Force has_tilelang() → False globally ────────────────────────────
# model.py calls has_tilelang() directly (not HAS_TILELANG) to set
# self.has_tilelang on each layer. Must patch the source function too.

IMPORT_UTILS_FILE = VLLM_SRC / "vllm/utils/import_utils.py"
IMPORT_UTILS_OLD = (
    'def has_tilelang() -> bool:\n'
    '    """Whether the optional `tilelang` package is available."""\n'
    '    return _has_module("tilelang")'
)
IMPORT_UTILS_NEW = (
    'def has_tilelang() -> bool:\n'
    '    """Whether the optional `tilelang` package is available."""\n'
    '    # gfx1030 (RDNA2) does not support rocWMMA required by TileLang kernels\n'
    '    return False'
)


def patch_once(target: Path, old: str, new: str) -> str:
    text = target.read_text()
    if new in text:
        return f"ALREADY_APPLIED {target.name}"
    if old not in text:
        print(f"WARNING: patch target not found in {target}", file=sys.stderr)
        print("Looking for:", repr(old[:120]), file=sys.stderr)
        return f"TARGET_NOT_FOUND {target}"
    if text.count(old) != 1:
        raise SystemExit(f"AMBIGUOUS_TARGET {target} (count={text.count(old)})")
    target.write_text(text.replace(old, new, 1))
    return f"PATCHED {target.name}"


def main():
    for target, old, new in [
        (ROUTER_FILE,       ROUTER_OLD,       ROUTER_NEW),
        (MXFP4_ORACLE_FILE, MXFP4_ORACLE_OLD, MXFP4_ORACLE_NEW),
        (MXFP4_ORACLE_FILE, MXFP4_CONVERT_OLD, MXFP4_CONVERT_NEW),
        (MHC_FILE,          MHC_OLD,           MHC_NEW),
        (IMPORT_UTILS_FILE, IMPORT_UTILS_OLD,  IMPORT_UTILS_NEW),
    ]:
        if not target.exists():
            raise SystemExit(f"File not found: {target}")
        result = patch_once(target, old, new)
        print(result)
        py_compile.compile(str(target), doraise=True)

    print("All patches applied, syntax OK")


if __name__ == "__main__":
    main()

# llama.cpp b7223 Upgrade Notes

**Date**: 2025-12-01
**Branch**: upgrade_b7223
**Upgrade**: b6872 → b7223 (351 commits)

## Changes Summary

### Version Info
- **Release**: b7223
- **Commit**: 98bd9ab1e4fdef1497da628574bb90d0890539e7
- **SHA256**: a604cd1f5453ec49620b7fa69f896dbc6e930ec644063c032d6932dce4a6f006

### CMake Changes
- **New option**: `LLAMA_HTTPLIB` - alternative to libcurl for HTTP downloads
  - Default: ON
  - Impact: None (we use `LLAMA_CURL=ON`)
  - New subdirectory: `vendor/cpp-httplib`

### Python Requirements Changes
- **transformers** (requirements-convert_legacy_llama.txt):
  - Before: `git+https://github.com/huggingface/transformers@v4.56.0-Embedding-Gemma-preview`
  - After: `transformers>=4.57.1,<5.0.0`
  - Reason: Embedding Gemma officially released
  - Impact: Compatible with existing recipe pins

- **gguf version**: No change (still 0.17.1)

### Patch Status

#### ✓ Patches that apply cleanly (6):
1. `fix-convert_lora_to_gguf.patch` - PASS
2. `fix-models-path.patch` - PASS
3. `hwcap_sve_check.patch` - PASS
4. `metal_gpu_selection.patch` - PASS
5. `mkl.patch` - PASS
6. `no-armv9-support-gcc11.patch` - PASS

#### ✗ Patches that need regeneration (4):
1. **disable-metal-bf16.patch**
   - Status: 1 out of 2 hunks FAILED
   - File: `ggml/src/ggml-metal/ggml-metal-device.m`
   - Action: Regenerate or check if still needed

2. **disable-metal-flash-attention.patch**
   - Status: 1 out of 1 hunks FAILED
   - File: `ggml/src/ggml-metal/ggml-metal-device.m`
   - Action: Regenerate or check if still needed

3. **increase-nmse-tolerance-aarch64.patch**
   - Status: 6 out of 7 hunks FAILED
   - File: `tests/test-backend-ops.cpp`
   - Action: Regenerate for new line numbers

4. **increase-nmse-tolerance.patch**
   - Status: Misordered hunks (entire patch fails)
   - File: `tests/test-backend-ops.cpp`
   - Action: Regenerate - code structure changed significantly

## Investigation Needed

### 1. Metal Patches
- **Question**: Are Metal BF16 and Flash Attention issues fixed upstream?
- **Action**: Test Metal builds without these patches to see if they pass
- **Rationale**: Upstream may have fixed the issues in the 351 commits

### 2. Numerical Tolerance Patches
- **Question**: Do the test-backend-ops tests still need tolerance adjustments?
- **Action**: Test builds without tolerance patches
- **Note**: Large code changes in test-backend-ops.cpp suggest major refactoring

### 3. New Features/Changes
- **Action**: Review changelog for breaking changes or new features
- **Commits**: 351 commits is substantial - may include API changes

## Next Steps

1. **Investigate upstream fixes**:
   ```bash
   cd /tmp/llama-compare/llama.cpp-b7223
   # Check if Metal issues are mentioned in recent commits
   git log b6872..b7223 --grep="metal" --grep="flash" --grep="bf16" --oneline
   ```

2. **Test without problematic patches**:
   - Try build without Metal patches
   - Try build without tolerance patches
   - See what actually fails

3. **Regenerate only necessary patches**:
   - Don't blindly regenerate - verify each patch is still needed
   - Upstream may have incorporated similar fixes

4. **Update recipe dependencies**:
   - No changes needed based on current analysis
   - transformers version compatible

5. **Test build**:
   - Local test build or push to CI
   - Check all platforms (Linux, macOS, Windows)
   - Check all variants (CPU, CUDA, Metal)

## Files Modified
- `recipe/meta.yaml` (version, commit, SHA256 updated)

## Progress Update (2025-12-01)

### Patch Cleanup Completed

Based on comprehensive patch analysis comparing with conda-forge b6191 (which has ZERO patches):

**Removed (2 patches)**:
- ✗ `increase-nmse-tolerance.patch` - Not needed (we skip test-backend-ops on GPU variants)
- ✗ `increase-nmse-tolerance-aarch64.patch` - Not needed (same reason)

**Commented Out for Re-evaluation (2 patches)**:
- ⏸ `disable-metal-bf16.patch` - May be fixed upstream in b7223
- ⏸ `disable-metal-flash-attention.patch` - May be fixed upstream in b7223

**Kept - All Apply Cleanly (6 patches)**:
- ✓ `mkl.patch` - MKL detection fix
- ✓ `metal_gpu_selection.patch` - Metal GPU selection for CI/headless
- ✓ `hwcap_sve_check.patch` - ARM64 old kernel compatibility
- ✓ `no-armv9-support-gcc11.patch` - GCC 11 ARM compatibility
- ✓ `fix-convert_lora_to_gguf.patch` - Python tool packaging
- ✓ `fix-models-path.patch` - Python tool packaging

**Patch Reduction**: 10 patches → 6 patches (40% reduction)

## Status
**IN PROGRESS** - Patches cleaned up, ready for test build or further optimization

// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#ifndef FLUTTER_SHELL_PLATFORM_WINDOWS_KIRAKARA_FLUTTER_COMPOSITOR_API_H_
#define FLUTTER_SHELL_PLATFORM_WINDOWS_KIRAKARA_FLUTTER_COMPOSITOR_API_H_

#include <stdint.h>

#if defined(__cplusplus)
extern "C" {
#endif

#define KIRAKARA_FLUTTER_COMPOSITOR_EXPORT_NAME \
  "FlutterDesktopKirakaraCompositorGetApi"
#define KIRAKARA_FLUTTER_COMPOSITOR_ABI_VERSION 1u
#define KIRAKARA_FLUTTER_COMPOSITOR_PATCHSET_VERSION 2u
#define KIRAKARA_FLUTTER_COMPOSITOR_PATCHSET_REVISION "windows-dcomp-synthetic"
#define KIRAKARA_FLUTTER_COMPOSITOR_ENGINE_REVISION \
  "a10d8ac38de835021c8d2f920dbf50a920ccc030"

typedef enum KirakaraFlutterCompositorResult {
  kKirakaraFlutterCompositorSuccess = 0,
  kKirakaraFlutterCompositorInvalidArgument = 1,
  kKirakaraFlutterCompositorVersionMismatch = 2,
  kKirakaraFlutterCompositorBusy = 3,
  kKirakaraFlutterCompositorUnavailable = 4,
  kKirakaraFlutterCompositorViewNotConfigured = 5,
} KirakaraFlutterCompositorResult;

typedef enum KirakaraFlutterCompositorConfigFlag {
  kKirakaraFlutterCompositorSyntheticStage = 1u << 0,
  kKirakaraFlutterCompositorRequireComposition = 1u << 1,
} KirakaraFlutterCompositorConfigFlag;

typedef enum KirakaraFlutterCompositorCapability {
  kKirakaraFlutterCompositorDirectComposition = 1ull << 0,
  kKirakaraFlutterCompositorPremultipliedAlpha = 1ull << 1,
  kKirakaraFlutterCompositorSyntheticStageProducer = 1ull << 2,
  kKirakaraFlutterCompositorIndependentStageProducer = 1ull << 3,
  kKirakaraFlutterCompositorCompositorClockPacing = 1ull << 4,
  kKirakaraFlutterCompositorInPlaceResize = 1ull << 5,
} KirakaraFlutterCompositorCapability;

typedef struct KirakaraFlutterCompositorConfig {
  uint32_t struct_size;
  uint32_t abi_version;
  uint32_t patchset_version;
  uint32_t flags;
  uintptr_t top_level_window;
  uint64_t reserved[4];
} KirakaraFlutterCompositorConfig;

typedef struct KirakaraFlutterCompositorDiagnostics {
  uint32_t struct_size;
  uint32_t abi_version;
  uint32_t patchset_version;
  uint32_t active;
  uint64_t capabilities;
  uintptr_t top_level_window;
  uint32_t width;
  uint32_t height;
  int32_t initialization_hresult;
  int32_t last_stage_present_hresult;
  int32_t last_stage_pacing_status;
  int32_t last_resize_hresult;
  uint64_t flutter_present_count;
  uint64_t stage_present_count;
  uint64_t stage_wait_wake_count;
  uint64_t stage_device_removed_count;
  uint64_t stage_occluded_count;
  uint64_t surface_resize_count;
  uint64_t composition_tree_commit_count;
  uint64_t reserved[2];
} KirakaraFlutterCompositorDiagnostics;

typedef int32_t (*KirakaraFlutterCompositorPrepareNextView)(
    const KirakaraFlutterCompositorConfig* config);
typedef int32_t (*KirakaraFlutterCompositorCancelPreparedView)(void);
typedef int32_t (*KirakaraFlutterCompositorGetViewDiagnostics)(
    uintptr_t flutter_view,
    KirakaraFlutterCompositorDiagnostics* diagnostics);

typedef struct KirakaraFlutterCompositorApi {
  uint32_t struct_size;
  uint32_t abi_version;
  uint32_t patchset_version;
  uint32_t reserved0;
  const char* patchset_revision;
  const char* engine_revision;
  KirakaraFlutterCompositorPrepareNextView prepare_next_view;
  KirakaraFlutterCompositorCancelPreparedView cancel_prepared_view;
  KirakaraFlutterCompositorGetViewDiagnostics get_view_diagnostics;
  uint64_t reserved[4];
} KirakaraFlutterCompositorApi;

typedef int32_t (*FlutterDesktopKirakaraCompositorGetApiProc)(
    uint32_t requested_abi_version,
    KirakaraFlutterCompositorApi* api);

#if defined(__cplusplus)
}  // extern "C"
#endif

#endif  // FLUTTER_SHELL_PLATFORM_WINDOWS_KIRAKARA_FLUTTER_COMPOSITOR_API_H_

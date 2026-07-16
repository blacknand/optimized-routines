/*
 * Single-precision vector lgamma(x) function.
 *
 * Copyright (c) 2026, Arm Limited.
 * SPDX-License-Identifier: MIT OR Apache-2.0 WITH LLVM-exception
 */

#define _GNU_SOURCE 1
#include <math.h>
#include "v_math.h"
#include "test_defs.h"

/* Single-precision correctly rounded vector lgammaf_r routine.
   This implementation loops over scalar lgammaf_r, but discards
   the sign information.  */
float32x4_t VPCS_ATTR NOINLINE V_NAME_F1 (lgamma) (float32x4_t x)
{
  int sign;
  float32x4_t y = vdupq_n_f32 (0.0f);

  y = vsetq_lane_f32 (lgammaf_r (vgetq_lane_f32 (x, 0), &sign), y, 0);
  y = vsetq_lane_f32 (lgammaf_r (vgetq_lane_f32 (x, 1), &sign), y, 1);
  y = vsetq_lane_f32 (lgammaf_r (vgetq_lane_f32 (x, 2), &sign), y, 2);
  y = vsetq_lane_f32 (lgammaf_r (vgetq_lane_f32 (x, 3), &sign), y, 3);

  return y;
}

HALF_WIDTH_ALIAS_F1 (lgamma)

TEST_ULP (V_NAME_F1 (lgamma), 0.0)
TEST_INTERVAL (V_NAME_F1 (lgamma), 0, inf, 20000)
TEST_INTERVAL (V_NAME_F1 (lgamma), -0, -inf, 20000)

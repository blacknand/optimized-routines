/*
 * Double-precision vector lgamma(x) function.
 *
 * Copyright (c) 2026, Arm Limited.
 * SPDX-License-Identifier: MIT OR Apache-2.0 WITH LLVM-exception
 */

#define _GNU_SOURCE 1
#include <math.h>
#include "v_math.h"
#include "test_defs.h"

/* Double-precision correctly rounded vector lgamma_r routine.
   This implementation loops over scalar lgamma_r, but discards
   the sign information.
   Worst-case ULP error is dependant on systemlib:
   For GLIBC 2.43 onwards, this is correctly rounded.
   For GLIBC versions prior to that, the maximum observed error is 6.54 + 0.5
   ULP:
   _ZGVnN2v_lgamma (-0x1.f613ab0969f81p+1)
    got -0x1.fac67c10ca5bap-2
   want -0x1.fac67c10ca5b3p-2.  */
float64x2_t VPCS_ATTR NOINLINE V_NAME_D1 (lgamma) (float64x2_t x)
{
  int sign;
  float64x2_t y = vdupq_n_f64 (0.0);

  y = vsetq_lane_f64 (lgamma_r (vgetq_lane_f64 (x, 0), &sign), y, 0);
  y = vsetq_lane_f64 (lgamma_r (vgetq_lane_f64 (x, 1), &sign), y, 1);

  return y;
}

TEST_ULP (V_NAME_D1 (lgamma), 6.55)
TEST_INTERVAL (V_NAME_D1 (lgamma), 0, inf, 20000)
TEST_INTERVAL (V_NAME_D1 (lgamma), -0, -inf, 20000)

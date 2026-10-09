/*
 * Modified version of the memset benchmark to act as a driver
 * for calling memset using the SPEC2017 CPU data, which can then be
 * used with spec stat and spec report.
*/

#include <stdio.h>
#include <string.h>
#include <stdint.h>
#include <assert.h>
#include "benchlib.h"

extern void* __memset_aarch64_sve(void* s, int c, size_t n);

typedef struct { uint16_t size; uint16_t freq; } freq_data_t;
typedef struct { uint8_t align; uint16_t freq; } align_data_t;
#define MAX_SIZE (1024 * 1024)

static freq_data_t memset_len_freq[] =
{
{40,28817}, {32,15336}, { 16,3823}, {296,3545}, { 24,3454}, {  8,1412},
{292,1202}, { 48, 927}, { 12, 613}, { 11, 539}, {284, 493}, {108, 414},
{ 88, 380}, { 20, 295}, {312, 271}, { 72, 233}, {  2, 200}, {  4, 192},
{ 15, 180}, { 14, 174}, { 13, 160}, { 56, 151}, { 36, 144}, { 64, 140},
{4095,133}, { 10, 130}, {  9, 124}, {  3, 124}, { 28, 120}, {  0, 118},
{288, 110}, {1152, 96}, {104,  90}, {  1,  86}, {832,  76}, {248,  74},
{1024, 69}, {120,  64}, {512,  63}, {384,  60}, {  6,  59}, { 80,  54},
{ 17,  50}, {  7,  49}, {520,  47}, {2048, 39}, {256,  37}, {864,  33},
{1440, 28}, { 22,  27}, {2056, 24}, {260,  23}, { 68,  23}, {  5,  22},
{ 18,  21}, {200,  18}, {2120, 18}, { 60,  17}, { 52,  16}, {336,  15},
{ 44,  13}, {192,  13}, {160,  12}, {2064, 12}, {128,  12}, { 76,  11},
{164,  11}, {152,  10}, {136,   9}, {488,   7}, { 96,   6}, {560,   6},
{1016,  6}, {112,   5}, {232,   5}, {168,   5}, {952,   5}, {184,   5},
{144,   4}, {252,   4}, { 84,   3}, {960,   3}, {3808,  3}, {244,   3},
{280,   3}, {224,   3}, {156,   3}, {1088,  3}, {440,   3}, {216,   2},
{304,   2}, { 23,   2}, { 25,   2}, { 26,   2}, {264,   2}, {328,   2},
{1096,  2}, {240,   2}, {1104,  2}, {704,   2}, {1664,  2}, {360,   2},
{808,   1}, {544,   1}, {236,   1}, {720,   1}, {368,   1}, {424,   1},
{640,   1}, {1112,  1}, {552,   1}, {272,   1}, {776,   1}, {376,   1},
{ 92,   1}, {536,   1}, {824,   1}, {496,   1}, {760,   1}, {792,   1},
{504,   1}, {344,   1}, {1816,  1}, {880,   1}, {176,   1}, {320,   1},
{352,   1}, {2008,  1}, {208,   1}, {408,   1}, {228,   1}, {2072,  1},
{568,   1}, {220,   1}, {616,   1}, {600,   1}, {392,   1}, {696,   1},
{2144,  1}, {1280,  1}, {2136,  1}, {632,   1}, {584,   1}, {456,   1},
{472,   1}, {3440,  1}, {2088,  1}, {680,   1}, {2928,  1}, {212,   1},
{648,   1}, {1752,  1}, {664,   1}, {3512,  1}, {1032,  1}, {528,   1},
{4072,  1}, {204,   1}, {2880,  1}, {3392,  1}, {712,   1}, { 59,   1},
{736,   1}, {592,   1}, {2520,  1}, {744,   1}, {196,   1}, {172,   1},
{728,   1}, {2040,  1}, {1192,  1}, {3600,  1}, {0, 0}
};

#define ALIGN_NUM 1024
#define SIZE_NUM 65536
#define SIZE_MASK (SIZE_NUM-1)
#define NUM_TESTS 32768
#define MIN_SIZE 32768
#define ITERS_RANDOM	20000
#define ITERS 5000

#define ALIGN_NUM 1024
#define ALIGN_MASK (ALIGN_NUM-1)

typedef struct { uint32_t offset : 20, len : 12; } memset_test_t;
static memset_test_t test_arr[NUM_TESTS];
static uint8_t a[MAX_SIZE + 4096] __attribute__((__aligned__(4096)));

static uint8_t align_arr[ALIGN_NUM];
static uint16_t len_arr[SIZE_NUM];

/* Alignment data for memset based on SPEC2017.  */
static align_data_t memset_align_freq[] =
{
 {16, 338}, {8, 307}, {32, 148}, {64, 131}, {4, 72}, {1, 23}, {2, 5}, {0, 0}
};

static void
init_memset_distribution (void)
{
  int i, j, freq, size, n;

  for (n = i = 0; (freq = memset_len_freq[i].freq) != 0; i++)
    for (j = 0, size = memset_len_freq[i].size; j < freq; j++)
      len_arr[n++] = size;
  assert (n == SIZE_NUM);

  for (n = i = 0; (freq = memset_align_freq[i].freq) != 0; i++)
    for (j = 0, size = memset_align_freq[i].align; j < freq; j++)
      align_arr[n++] = size - 1;
  assert (n == ALIGN_NUM);
}

static void
init_memset (size_t max_size)
{
  /* Create a random set of memsets with the given size and alignment
     distributions.  */
  for (int i = 0; i < NUM_TESTS; i++)
    {
      test_arr[i].offset = (rand32 (0) & (max_size - 1));
      test_arr[i].offset &= ~align_arr[rand32 (0) & ALIGN_MASK];
      test_arr[i].len = len_arr[rand32 (0) & SIZE_MASK];
    }
}

static void inline __attribute ((always_inline))
memset_random ()
{
  uint64_t memset_size;
  rand32 (0x12345678);

  for (uint64_t size = MIN_SIZE; size <= MAX_SIZE; size *= 2)
    {
      init_memset (size) ;

      for (int c = 0; c < NUM_TESTS; c++)
	__memset_aarch64_sve (a + test_arr[c].offset, 0, test_arr[c].len);

      for (int i = 0; i < ITERS_RANDOM; i++) {
	for (int c = 0; c < NUM_TESTS; c++)
	  __memset_aarch64_sve (a + test_arr[c].offset, 0, test_arr[c].len);
      }
    }
}

static void inline __attribute ((always_inline))
memset_deterministic()
{
  for (uint64_t size = 8; size <= 2048; size *= 2)
    {
      for (int i = 0; i < ITERS; i++)
	__memset_aarch64_sve (a, 0, size);
    }
}

int main(int argc, char **argv)
{
  int use_random = strcmp(argv[1], "--random") == 0;
  int use_deterministic = strcmp(argv[1], "--deterministic") == 0;
  if (use_random) init_memset_distribution();
  memset (a, 1, sizeof (a));
  if (use_random) memset_random();
  if (use_deterministic) memset_deterministic();
  return 0;
}
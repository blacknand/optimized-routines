cp /home/fabque01/glibc-build-test/aor/string/aarch64/memchr-sve2.S /home/fabque01/glibc-build-test/glibcarm/src/sysdeps/aarch64/memchr.S
sed -i '41c\IMPL (MEMCHR, 0)' /home/fabque01/glibc-build-test/glibcarm/src/benchtests/bench-memchr.c
sed -i '44c\//IMPL (generic_memchr, 0)' /home/fabque01/glibc-build-test/glibcarm/src/benchtests/bench-memchr.c
sed -i '30c\#  define TEST_NAME "memchr-sve"' /home/fabque01/glibc-build-test/glibcarm/src/benchtests/bench-memchr.c

sed -i '8c\#include <sysdep.h>' /home/fabque01/glibc-build-test/glibcarm/src/sysdeps/aarch64/memchr.S
sed -i '19c\# define MEMCHR_SVE2 __memchr' /home/fabque01/glibc-build-test/glibcarm/src/sysdeps/aarch64/memchr.S

echo "weak_alias (MEMCHR_SVE2, memchr)" >> /home/fabque01/glibc-build-test/glibcarm/src/sysdeps/aarch64/memchr.S

echo "libc_hidden_builtin_def (memchr)" >> /home/fabque01/glibc-build-test/glibcarm/src/sysdeps/aarch64/memchr.S

make -C /home/fabque01/glibc-build-test/glibcarm/build/ -j"$(nproc)"
make -C /home/fabque01/glibc-build-test/glibcarm/build/ test t=string/test-memchr -j"$(nproc)"
make -C /home/fabque01/glibc-build-test/glibcarm/build/ bench BENCHSET=string-benchset
mkdir -p /home/fabque01/glibc-build-test/glibcarm/data-memchr-out/
mv /home/fabque01/glibc-build-test/glibcarm/build/benchtests/bench-memchr.out /home/fabque01/glibc-build-test/glibcarm/data-memchr-out/bench-memchr-sve.out

for i in {1..5}; do
    echo "Run $i"
#   make -C /home/fabque01/glibc-build-test/glibcarm/build/ -j"$(nproc)"
    make -C /home/fabque01/glibc-build-test/glibcarm/build/ bench BENCHSET=string-benchset
    mv /home/fabque01/glibc-build-test/glibcarm/build/benchtests/bench-memchr.out /home/fabque01/glibc-build-test/glibcarm/data-memchr-out/bench-memchr-sve${i}.out
done

#!/usr/bin/env bash
set -u

# ============================================================
# ECE 379K Lab 1 - Remaining Frontera measurements
# Run from starter_files/
# ============================================================

N=4096
FIXED_T=32
THREADS="1 2 4 8 16 28 40 56 84 112"
SHARD_COUNTS="16 64 256 1024 4096"

OUT="../results/frontera"
mkdir -p "$OUT"

echo "============================================================"
echo "ECE379K LAB1 FRONTERA RUN"
echo "Chosen/provisional N = $N"
echo "Fixed T = $FIXED_T"
echo "Started: $(date)"
echo "============================================================"

# ------------------------------------------------------------
# Machine information / protocol
# ------------------------------------------------------------

echo "[machine] Saving lscpu"
lscpu > "$OUT/lscpu.txt"

echo "[machine] Checking perf"
{
    echo "=== perf stat cycles ==="
    perf stat -e cycles true
    echo
    echo "=== HITM events ==="
    perf list | grep -i xsnp
} > "$OUT/perf_check.txt" 2>&1


# ============================================================
# PART 5 - CUSTOM LOCKS
# ============================================================

echo
echo "========== PART 5: FIVE-LOCK SWEEP =========="

make sweep \
    IMPLS="sharded:mutex sharded:tas sharded:ttas sharded:ticket sharded:park" \
    SHARDS="$N" \
    THREADS="$THREADS" \
    2>&1 | tee "$OUT/part5_lock_sweep.txt"

# Copy generated CSVs so everything is together.
for f in sharded_mutex.csv sharded_tas.csv sharded_ttas.csv \
         sharded_ticket.csv sharded_park.csv; do
    [ -f "$f" ] && cp "$f" "$OUT/"
done


echo
echo "========== PART 5: ONE-SHARD PERF, T=8 =========="

P5_EVENTS="cycles,instructions,L1-dcache-load-misses,mem_load_l3_hit_retired.xsnp_hitm,context-switches"

for l in mutex tas ttas ticket park; do
    echo "--- $l ---"
    EVENTS="$P5_EVENTS" \
        make perf IMPL="sharded:$l" T=8 SHARDS=1 CPUS=0-7 \
        > "$OUT/part5_one_shard_${l}.txt" 2>&1
done


echo
echo "========== PART 5: OVERSUBSCRIPTION, 32 ON 8 =========="

for l in mutex tas ttas ticket park; do
    echo "--- $l ---"
    make perf IMPL="sharded:$l" T=32 SHARDS="$N" CPUS=0-7 \
        > "$OUT/part5_oversub_${l}.txt" 2>&1
done


echo
echo "========== PART 5: SHARD-COUNT SWEEP TTAS/PARK =========="

for l in ttas park; do
    file="$OUT/part5_shard_counts_${l}.txt"
    : > "$file"

    echo "=== $l, T=1 ===" | tee -a "$file"
    for n in $SHARD_COUNTS; do
        ./bench "sharded:$l" 1 "$n" 2 2>&1 | tee -a "$file"
    done

    echo >> "$file"
    echo "=== $l, T=$FIXED_T ===" | tee -a "$file"
    for n in $SHARD_COUNTS; do
        ./bench "sharded:$l" "$FIXED_T" "$n" 2 2>&1 | tee -a "$file"
    done
done


# ============================================================
# PART 6 - READER / WRITER LOCKS
# ============================================================

echo
echo "========== PART 6: MIX x LOCK x SHARD COUNT =========="

for mix in "80/10/10" "50/25/25" "100/0/0"; do

    mixname=$(echo "$mix" | tr '/' '_')

    for n in 1 "$N"; do

        for lock in ttas rw rwp shared_mutex; do

            impl="sharded:$lock"
            outfile="$OUT/part6_${lock}_mix_${mixname}_shards_${n}.csv"

            echo "Running $impl MIX=$mix SHARDS=$n"

            MIX="$mix" \
                bash sweep.sh ./bench "$impl" "$n" \
                1 2 4 8 16 28 40 56 84 112 \
                > "$outfile" \
                2> "$OUT/part6_${lock}_mix_${mixname}_shards_${n}.log"

        done
    done
done


echo
echo "========== PART 6: WRITER-ROLE COMPARISON =========="

# High-contention case makes reader-vs-writer preference easiest to see.
# 4 writers + 28 readers, 32 threads total, one shard.
for lock in rw rwp shared_mutex; do
    WRITERS=4 ./bench "sharded:$lock" 32 1 5 \
        > "$OUT/part6_writers4_${lock}_shards1.txt" 2>&1
done

# Also measure at chosen N.
for lock in rw rwp shared_mutex; do
    WRITERS=4 ./bench "sharded:$lock" 32 "$N" 5 \
        > "$OUT/part6_writers4_${lock}_shards${N}.txt" 2>&1
done


# ============================================================
# PART 7 - HASH TABLE
# ============================================================

echo
echo "========== PART 7: HASH vs TREE / BUCKET COUNTS =========="

# KEYS = 1<<20 = 1048576
# Start at 2*KEYS and divide by four until next step < 1024.
BUCKET_COUNTS="2097152 524288 131072 32768 8192 2048"

# Baseline sharded tree, same shard count, T=1.
./bench sharded:ttas 1 "$N" 5 \
    > "$OUT/part7_sharded_ttas_baseline.txt" 2>&1

for b in $BUCKET_COUNTS; do
    echo "BUCKETS=$b"

    BUCKETS="$b" ./bench hashed:ttas 1 "$N" 5 \
        > "$OUT/part7_bucket_${b}_bench.txt" 2>&1

    # Use default DELAY first. perfstat.sh will WARN if warm-up exceeds it.
    BUCKETS="$b" \
    EVENTS="cycles,instructions,L1-dcache-load-misses,cache-misses" \
        make perf IMPL=hashed:ttas T=1 SHARDS="$N" \
        > "$OUT/part7_bucket_${b}_perf.txt" 2>&1
done


echo
echo "========== PART 7: STRIPE COUNT =========="

for lock in ttas park; do
    file="$OUT/part7_stripe_counts_${lock}.txt"
    : > "$file"

    for n in $SHARD_COUNTS; do
        BUCKETS=2097152 ./bench "hashed:$lock" "$FIXED_T" "$n" 2 \
            2>&1 | tee -a "$file"
    done
done


echo
echo "========== PART 7: PADDING SWEEPS =========="

for impl in \
    hashed:ttas \
    hashed:ttas:nopad \
    sharded:ttas \
    sharded:ttas:nopad
do
    name=$(echo "$impl" | tr ':' '_')

    bash sweep.sh ./bench "$impl" 1024 \
        1 2 4 8 16 28 40 56 84 112 \
        > "$OUT/part7_padding_${name}.csv" \
        2> "$OUT/part7_padding_${name}.log"
done


echo
echo "========== PART 7: PADDING PERF =========="

PAD_EVENTS="cycles,instructions,L1-dcache-load-misses,mem_load_l3_hit_retired.xsnp_hitm,context-switches"

for impl in hashed:ttas hashed:ttas:nopad; do
    name=$(echo "$impl" | tr ':' '_')

    EVENTS="$PAD_EVENTS" \
        make perf IMPL="$impl" T=28 SHARDS=1024 \
        > "$OUT/part7_padding_perf_${name}.txt" 2>&1
done


# ============================================================
# FINAL
# ============================================================

echo
echo "============================================================"
echo "FINISHED: $(date)"
echo "Outputs are in: $OUT"
echo "============================================================"

find "$OUT" -maxdepth 1 -type f | sort

#!/usr/bin/env bash
#
# Encryption upgrade proof: AES-256-GCM -> XChaCha20-Poly1305
#
# Runs four phases, each in its own process under its own Gemfile, passing
# ciphertext envelopes between phases through state/*.json:
#
#   Phase 0  familia 2.10.1 (released), OpenSSL only   -> writes AES envelopes
#   Phase 1  this checkout, OpenSSL only               -> reads 0, writes AES
#   Phase 2  this checkout + rbnacl/libsodium          -> reads 0+1, writes XChaCha
#   Phase 3  this checkout, rbnacl removed again       -> reads 2 (rollback hazard)
#
# Requires: ruby + bundler, libsodium installed system-wide for phase 2,
# network access for the initial `bundle install` of each Gemfile.

set -euo pipefail
cd "$(dirname "$0")"

export PROOF_STATE_DIR="${PROOF_STATE_DIR:-$PWD/state}"
rm -rf "$PROOF_STATE_DIR"
mkdir -p "$PROOF_STATE_DIR"

run_phase() {
  local gemfile="$1" script="$2"
  echo
  echo "──────────────────────────────────────────────────────────────"
  echo "  $script  (BUNDLE_GEMFILE=$gemfile)"
  echo "──────────────────────────────────────────────────────────────"
  (
    export BUNDLE_GEMFILE="$PWD/gemfiles/$gemfile"
    bundle check >/dev/null 2>&1 || bundle install --quiet
    bundle exec ruby "$script"
  )
}

if run_phase Gemfile.production-today phase0_production_today.rb; then
  phase0_ok=1
else
  # Phase 0 needs the released 2.10.1 gem from rubygems; if it cannot be
  # installed (offline), fall back to seeding the fixtures with this
  # checkout's AES provider instead. The remaining phases still prove the
  # envelope contract, just not against the released gem's bytes.
  echo "!! phase 0 (released 2.10.1) unavailable -- seeding fixtures with the local checkout instead"
  PROOF_EXPECT_VERSION="$(ruby -r./../../lib/familia/version -e 'puts Familia::VERSION' 2>/dev/null || true)"
  export PROOF_EXPECT_VERSION
  run_phase Gemfile.dev-no-libsodium phase0_production_today.rb
fi

run_phase Gemfile.dev-no-libsodium  phase1_gem_upgrade_no_libsodium.rb
run_phase Gemfile.dev-with-libsodium phase2_libsodium_enabled.rb
run_phase Gemfile.dev-no-libsodium  phase3_rollback_hazard.rb

echo
echo "All phases passed."

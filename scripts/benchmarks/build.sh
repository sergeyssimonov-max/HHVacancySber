#!/bin/bash
set -euo pipefail
# Usage: bash scripts/benchmarks/build.sh /absolute/scratch/output-binary
if [[ $# != 1 || "$1" != /* || ! -d "$(dirname "$1")" ]]; then
    echo 'Pass an absolute output binary path in an existing scratch directory.' >&2
    exit 2
fi
benchmark_root="$(cd "$(dirname "$0")/../.." && pwd)"
benchmark_sources="$benchmark_root/HHVacancySber/HHVacancySber"
swiftc -O -parse-as-library -module-cache-path "$(dirname "$1")/module-cache" \
    "$benchmark_sources/HHModels.swift" "$benchmark_sources/HHAPIClient.swift" \
    "$benchmark_sources/HHAuthConfig.swift" "$benchmark_sources/AreaDirectoryStore.swift" \
    "$benchmark_sources/VacancySnapshotStore.swift" "$benchmark_sources/ApplicationSupportLocation.swift" "$benchmark_sources/EmployerConfiguration.swift" \
    "$benchmark_sources/FavoriteVacancyStore.swift" "$benchmark_sources/FavoriteVacanciesPDFExporter.swift" \
    "$benchmark_sources/VacancyCollectionService.swift" "$benchmark_sources/VacancySearchViewModel.swift" \
    "$benchmark_root/scripts/benchmarks/RuntimeBenchmarks.swift" -o "$1"

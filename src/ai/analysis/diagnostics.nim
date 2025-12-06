## Diagnostic Metrics Collection System
##
## REFACTORED: 2025-12-06 - Modular architecture (9 sub-modules)
##
## This module re-exports all diagnostic functionality from the sub-module structure:
## - types.nim: Core types (DiagnosticMetrics, DiagnosticSession)
## - 6 advisor collectors (Domestikos, Logothete, Drungarius, Eparch, Protostrator, Basileus)
## - csv_writer.nim: CSV I/O
## - orchestrator.nim: Main collectDiagnostics proc
##
## WHY REFACTOR:
## - Old: 1,394-line monolith violating CLAUDE.md guidelines
## - New: 9 modules (~60-280 lines each), aligned with RBA advisor hierarchy
## - Added: 3 new fields (totalSpaceports, totalShipyards, advisorReasoning)
## - Fixed: Gap #9 (advisor reasoning visibility), Gap #10 (facility tracking)

# Re-export types
import diagnostics/types
export types

# Re-export orchestrator (main public API)
import diagnostics/orchestrator
export orchestrator.collectDiagnostics

# Re-export CSV writer
import diagnostics/csv_writer
export csv_writer.writeCSVHeader, csv_writer.writeCSVRow,
       csv_writer.writeDiagnosticsCSV

# Re-export individual collectors (for testing or direct use)
import diagnostics/domestikos_collector
import diagnostics/logothete_collector
import diagnostics/drungarius_collector
import diagnostics/eparch_collector
import diagnostics/protostrator_collector
import diagnostics/basileus_collector

export domestikos_collector.collectDomestikosMetrics
export logothete_collector.collectLogotheteMetrics
export drungarius_collector.collectDrungariusMetrics
export eparch_collector.collectEparchMetrics
export protostrator_collector.collectProtostratorMetrics
export basileus_collector.collectBasileusMetrics

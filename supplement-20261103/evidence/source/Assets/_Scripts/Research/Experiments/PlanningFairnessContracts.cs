using System;
using System.Collections.Generic;
using DDM.Research.Navigation;
using DDM.Research.Scenarios;

namespace DDM.Research.Experiments
{
    public sealed class PlanningAlgorithmFairnessProfile
    {
        public string AlgorithmId { get; private set; }
        public string SpecificationId { get; private set; }
        public string SpecificationRelativePath { get; private set; }
        public string ImplementationRelativePath { get; private set; }
        public string StateModelId { get; private set; }
        public string ProcessedWorkUnit { get; private set; }
        public string NativeMetricsSemanticsId { get; private set; }
        public bool UsesPerAgentState { get; private set; }
        public bool UsesSharedField { get; private set; }

        internal PlanningAlgorithmFairnessProfile(
            string algorithmId,
            string specificationId,
            string specificationRelativePath,
            string implementationRelativePath,
            string stateModelId,
            string processedWorkUnit,
            string nativeMetricsSemanticsId,
            bool usesPerAgentState,
            bool usesSharedField)
        {
            AlgorithmId = algorithmId;
            SpecificationId = specificationId;
            SpecificationRelativePath = specificationRelativePath;
            ImplementationRelativePath = implementationRelativePath;
            StateModelId = stateModelId;
            ProcessedWorkUnit = processedWorkUnit;
            NativeMetricsSemanticsId = nativeMetricsSemanticsId;
            UsesPerAgentState = usesPerAgentState;
            UsesSharedField = usesSharedField;
        }
    }

    public sealed class PlanningFairnessClassification
    {
        public string GoalCohortId { get; private set; }
        public string ComparisonCohortId { get; private set; }
        public int DistinctGoalCount { get; private set; }
        public int PlannerInstanceCount { get; private set; }
        public int PersistentStateInstanceCount { get; private set; }
        public int SharedFieldInstanceCount { get; private set; }

        internal PlanningFairnessClassification(
            string goalCohortId,
            string comparisonCohortId,
            int distinctGoalCount,
            int plannerInstanceCount,
            int persistentStateInstanceCount,
            int sharedFieldInstanceCount)
        {
            GoalCohortId = goalCohortId;
            ComparisonCohortId = comparisonCohortId;
            DistinctGoalCount = distinctGoalCount;
            PlannerInstanceCount = plannerInstanceCount;
            PersistentStateInstanceCount = persistentStateInstanceCount;
            SharedFieldInstanceCount = sharedFieldInstanceCount;
        }
    }

    [Serializable]
    public sealed class PlanningRunProvenance
    {
        public const int CurrentSchemaVersion = 1;

        public int schemaVersion = CurrentSchemaVersion;
        public string fairnessProtocolId;
        public string fairnessProtocolRelativePath;
        public string fairnessProtocolSha256;
        public string algorithmId;
        public string algorithmSpecificationId;
        public string algorithmSpecificationRelativePath;
        public string algorithmSpecificationSha256;
        public string algorithmImplementationRelativePath;
        public string algorithmImplementationSha256;
        public string workloadSpecificationId;
        public string workloadSpecificationRelativePath;
        public string workloadSpecificationSha256;
    }

    public static class PlanningFairnessContracts
    {
        public const int FairnessSchemaVersion = 1;
        public const string FairnessProtocolId = "four-algorithm-fairness-v1";
        public const string FairnessProtocolRelativePath = "Research/Four_Algorithm_Fairness_and_Unified_Campaign_Specification.md";
        public const string Gate13RAX2FairnessProtocolId = "gate13r-ax2-four-algorithm-fairness-v1";
        public const string Gate13RAX2FairnessProtocolRelativePath = "Research/Gate13R-AX2/Contracts/four-algorithm-extension-fairness.v1.md";
        public const string WorkloadSpecificationId = "fixed-start-planning-workload-v1";
        public const string WorkloadSpecificationRelativePath = "Research/Scenario_IO_and_Planning_Workload_Specification.md";

        public const string GoalCohortSingleShared = "single-shared-goal-v1";
        public const string GoalCohortHeterogeneous = "heterogeneous-goal-v1";
        public const string FourAlgorithmSharedGoalCohort = "four-algorithm-shared-goal-v1";
        public const string Gate13RAX2SharedGoalCohort = "gate13r-ax2-shared-goal-v1";
        public const string PerAgentHeterogeneousGoalCohort = "per-agent-heterogeneous-goal-v1";
        public const string GroupedFieldHeterogeneousGoalCohort = "grouped-field-heterogeneous-goal-v1";

        private static readonly PlanningAlgorithmFairnessProfile[] Profiles =
        {
            new PlanningAlgorithmFairnessProfile(
                NavigationAlgorithmIds.AStarRepeated,
                "a-star-repeated-v1",
                "Research/AStar_Repeated_Specification.md",
                "Assets/_Scripts/Research/Algorithms/AStarRepeatedPlanner.cs",
                "stateless-per-request-v1",
                "nodes",
                "astar-expanded-relaxed-v1",
                false,
                false),
            new PlanningAlgorithmFairnessProfile(
                NavigationAlgorithmIds.DStarLite,
                "d-star-lite-v1",
                "Research/DStar_Lite_Specification.md",
                "Assets/_Scripts/Research/Algorithms/DStarLitePlanner.cs",
                "persistent-per-agent-v1",
                "nodes",
                "dstar-expanded-relaxed-repaired-v1",
                true,
                false),
            new PlanningAlgorithmFairnessProfile(
                NavigationAlgorithmIds.CorrectedFullRecomputeFlowField,
                "corrected-full-recompute-flow-field-v1",
                "Research/Corrected_Full_Recompute_Flow_Field_Specification.md",
                "Assets/_Scripts/Research/Algorithms/CorrectedFullRecomputeFlowFieldPlanner.cs",
                "single-shared-multisource-field-v1",
                "cells",
                "cff-expanded-relaxed-full-rebuild-v1",
                false,
                true),
            new PlanningAlgorithmFairnessProfile(
                NavigationAlgorithmIds.IncrementalDynamicFlowField,
                "incremental-dynamic-flow-field-v1",
                "Research/Incremental_Dynamic_Flow_Field_Specification.md",
                "Assets/_Scripts/Research/Algorithms/IncrementalDynamicFlowFieldPlanner.cs",
                "single-shared-incremental-multisource-field-v1",
                "cells",
                "idff-expanded-relaxed-incremental-repair-v1",
                false,
                true)
        };

        // Gate 13R-AX2 extends the registered algorithm set without changing the
        // four-profile Gate 10/Gate 13R registry exposed through AuthorizedProfiles.
        private static readonly PlanningAlgorithmFairnessProfile[] Gate13RAX2Profiles =
        {
            new PlanningAlgorithmFairnessProfile(
                NavigationAlgorithmIds.BidirectionalAStarRepeated,
                "bidirectional-a-star-repeated-v1",
                "Research/Gate13R-AX2/Algorithms/Bidirectional_A_Star_Repeated_Specification.v1.md",
                "Assets/_Scripts/Research/Algorithms/BidirectionalAStarRepeatedPlanner.cs",
                "stateless-per-request-v1",
                "nodes",
                "biastar-expanded-relaxed-v1",
                false,
                false),
            new PlanningAlgorithmFairnessProfile(
                NavigationAlgorithmIds.LifelongPlanningAStar,
                "lifelong-planning-a-star-fixed-start-v1",
                "Research/Gate13R-AX2/Algorithms/Lifelong_Planning_A_Star_Specification.v1.md",
                "Assets/_Scripts/Research/Algorithms/LifelongPlanningAStarPlanner.cs",
                "persistent-per-agent-fixed-start-v1",
                "nodes",
                "lpa-expanded-relaxed-repaired-v1",
                true,
                false)
        };

        public static IReadOnlyList<PlanningAlgorithmFairnessProfile> AuthorizedProfiles
        {
            get { return Array.AsReadOnly(Profiles); }
        }

        public static PlanningAlgorithmFairnessProfile GetProfile(string algorithmId)
        {
            for (int index = 0; index < Profiles.Length; index++)
            {
                if (string.Equals(Profiles[index].AlgorithmId, algorithmId, StringComparison.Ordinal)) return Profiles[index];
            }
            for (int index = 0; index < Gate13RAX2Profiles.Length; index++)
            {
                if (string.Equals(Gate13RAX2Profiles[index].AlgorithmId, algorithmId, StringComparison.Ordinal)) return Gate13RAX2Profiles[index];
            }
            throw new NotSupportedException("Algorithm has no authorized Gate 10 fairness profile: " + algorithmId);
        }

        public static string[] GetAlgorithmsForComparisonCohort(string comparisonCohortId)
        {
            if (string.Equals(comparisonCohortId, FourAlgorithmSharedGoalCohort, StringComparison.Ordinal))
            {
                return new[]
                {
                    NavigationAlgorithmIds.AStarRepeated,
                    NavigationAlgorithmIds.DStarLite,
                    NavigationAlgorithmIds.CorrectedFullRecomputeFlowField,
                    NavigationAlgorithmIds.IncrementalDynamicFlowField
                };
            }
            if (string.Equals(comparisonCohortId, Gate13RAX2SharedGoalCohort, StringComparison.Ordinal))
            {
                return new[]
                {
                    NavigationAlgorithmIds.BidirectionalAStarRepeated,
                    NavigationAlgorithmIds.LifelongPlanningAStar,
                    NavigationAlgorithmIds.CorrectedFullRecomputeFlowField,
                    NavigationAlgorithmIds.IncrementalDynamicFlowField
                };
            }
            if (string.Equals(comparisonCohortId, PerAgentHeterogeneousGoalCohort, StringComparison.Ordinal))
            {
                return new[] { NavigationAlgorithmIds.AStarRepeated, NavigationAlgorithmIds.DStarLite };
            }
            if (string.Equals(comparisonCohortId, GroupedFieldHeterogeneousGoalCohort, StringComparison.Ordinal))
            {
                return new[] { NavigationAlgorithmIds.CorrectedFullRecomputeFlowField, NavigationAlgorithmIds.IncrementalDynamicFlowField };
            }
            throw new NotSupportedException("Comparison cohort is not authorized: " + comparisonCohortId);
        }

        public static PlanningFairnessClassification Classify(ResolvedDeterministicScenario scenario, string algorithmId)
        {
            if (scenario == null) throw new ArgumentNullException("scenario");
            PlanningAlgorithmFairnessProfile profile = GetProfile(algorithmId);
            int distinctGoalCount = CountDistinctGoals(scenario.Agents);
            bool shared = distinctGoalCount == 1;
            string goalCohortId = shared ? GoalCohortSingleShared : GoalCohortHeterogeneous;
            string comparisonCohortId;
            if (shared) comparisonCohortId = FourAlgorithmSharedGoalCohort;
            else comparisonCohortId = profile.UsesSharedField ? GroupedFieldHeterogeneousGoalCohort : PerAgentHeterogeneousGoalCohort;

            int persistentStateCount = profile.UsesPerAgentState
                ? scenario.Agents.Count
                : (profile.UsesSharedField ? 1 : 0);
            int fieldCount = profile.UsesSharedField ? 1 : 0;
            return new PlanningFairnessClassification(
                goalCohortId,
                comparisonCohortId,
                distinctGoalCount,
                1,
                persistentStateCount,
                fieldCount);
        }

        public static PlanningFairnessClassification Classify(
            ResolvedDeterministicScenario scenario,
            string algorithmId,
            PlanningRunProvenance provenance)
        {
            if (provenance == null ||
                !string.Equals(provenance.fairnessProtocolId, Gate13RAX2FairnessProtocolId, StringComparison.Ordinal))
            {
                return Classify(scenario, algorithmId);
            }
            if (scenario == null) throw new ArgumentNullException("scenario");
            PlanningAlgorithmFairnessProfile profile = GetProfile(algorithmId);
            int distinctGoalCount = CountDistinctGoals(scenario.Agents);
            if (distinctGoalCount != 1)
            {
                throw new InvalidOperationException("Gate 13R-AX2 is restricted to the frozen single-shared-goal campaigns.");
            }
            RequireAlgorithmAuthorizedForCohort(algorithmId, Gate13RAX2SharedGoalCohort);
            int persistentStateCount = profile.UsesPerAgentState
                ? scenario.Agents.Count
                : (profile.UsesSharedField ? 1 : 0);
            return new PlanningFairnessClassification(
                GoalCohortSingleShared,
                Gate13RAX2SharedGoalCohort,
                distinctGoalCount,
                1,
                persistentStateCount,
                profile.UsesSharedField ? 1 : 0);
        }

        public static void RequireAlgorithmAuthorizedForCohort(string algorithmId, string comparisonCohortId)
        {
            string[] algorithms = GetAlgorithmsForComparisonCohort(comparisonCohortId);
            for (int index = 0; index < algorithms.Length; index++)
            {
                if (string.Equals(algorithms[index], algorithmId, StringComparison.Ordinal)) return;
            }
            throw new InvalidOperationException(string.Format(
                "Algorithm {0} is not authorized for comparison cohort {1}.",
                algorithmId,
                comparisonCohortId));
        }

        public static void ValidateProvenance(PlanningRunProvenance provenance, string algorithmId)
        {
            if (provenance == null) throw new ArgumentNullException("provenance");
            PlanningAlgorithmFairnessProfile profile = GetProfile(algorithmId);
            bool isAX2 = string.Equals(provenance.fairnessProtocolId, Gate13RAX2FairnessProtocolId, StringComparison.Ordinal);
            bool protocolMatches = isAX2
                ? string.Equals(provenance.fairnessProtocolRelativePath, Gate13RAX2FairnessProtocolRelativePath, StringComparison.Ordinal)
                : string.Equals(provenance.fairnessProtocolId, FairnessProtocolId, StringComparison.Ordinal) &&
                  string.Equals(provenance.fairnessProtocolRelativePath, FairnessProtocolRelativePath, StringComparison.Ordinal);
            bool isAX2OnlyAlgorithm = string.Equals(algorithmId, NavigationAlgorithmIds.BidirectionalAStarRepeated, StringComparison.Ordinal) ||
                                      string.Equals(algorithmId, NavigationAlgorithmIds.LifelongPlanningAStar, StringComparison.Ordinal);
            if (provenance.schemaVersion != PlanningRunProvenance.CurrentSchemaVersion ||
                !protocolMatches ||
                (isAX2OnlyAlgorithm && !isAX2) ||
                !string.Equals(provenance.algorithmId, algorithmId, StringComparison.Ordinal) ||
                !string.Equals(provenance.algorithmSpecificationId, profile.SpecificationId, StringComparison.Ordinal) ||
                !string.Equals(provenance.algorithmSpecificationRelativePath, profile.SpecificationRelativePath, StringComparison.Ordinal) ||
                !string.Equals(provenance.algorithmImplementationRelativePath, profile.ImplementationRelativePath, StringComparison.Ordinal) ||
                !string.Equals(provenance.workloadSpecificationId, WorkloadSpecificationId, StringComparison.Ordinal) ||
                !string.Equals(provenance.workloadSpecificationRelativePath, WorkloadSpecificationRelativePath, StringComparison.Ordinal) ||
                !IsSha256(provenance.fairnessProtocolSha256) ||
                !IsSha256(provenance.algorithmSpecificationSha256) ||
                !IsSha256(provenance.algorithmImplementationSha256) ||
                !IsSha256(provenance.workloadSpecificationSha256))
            {
                throw new InvalidOperationException("Planning-run provenance is incomplete or does not match the authorized algorithm profile.");
            }
        }

        public static bool IsSha256(string value)
        {
            if (string.IsNullOrEmpty(value) || value.Length != 64) return false;
            for (int index = 0; index < value.Length; index++)
            {
                char character = value[index];
                bool digit = character >= '0' && character <= '9';
                bool lower = character >= 'a' && character <= 'f';
                if (!digit && !lower) return false;
            }
            return true;
        }

        private static int CountDistinctGoals(IReadOnlyList<ResolvedScenarioAgent> agents)
        {
            HashSet<GridCoordinate> goals = new HashSet<GridCoordinate>();
            for (int index = 0; index < agents.Count; index++) goals.Add(agents[index].Goal);
            return goals.Count;
        }
    }
}

using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using DDM.Research.Grid;
using DDM.Research.Logging;
using DDM.Research.Navigation;
using DDM.Research.Scenarios;

namespace DDM.Research.Experiments
{
    public enum ExperimentRunnerState
    {
        Created,
        Initialized,
        Running,
        Completed,
        Faulted,
        Disposed
    }

    [Serializable]
    public sealed class ExperimentRunnerLifecycleRecord
    {
        public string scenarioId;
        public string scenarioFingerprintSha256;
        public string algorithmId;
        public string state;
        public long simulationTick;
        public string message;
    }

    public sealed class ExperimentRepairObservation
    {
        public string EventId { get; private set; }
        public long SimulationTick { get; private set; }
        public NavigationChangeSet ChangeSet { get; private set; }
        public NavigationRepairResult Result { get; private set; }

        internal ExperimentRepairObservation(string eventId, long simulationTick, NavigationChangeSet changeSet, NavigationRepairResult result)
        {
            EventId = eventId;
            SimulationTick = simulationTick;
            ChangeSet = changeSet;
            Result = result;
        }
    }

    /// <summary>
    /// Single-threaded experiment lifecycle skeleton. It owns deterministic tick/event
    /// ordering and delegates all planning and repair work to an injected planner.
    /// It intentionally contains no pathfinding or unit-movement implementation.
    /// </summary>
    public sealed class ExperimentRunner : IDisposable
    {
        private readonly string runId;
        private readonly DeterministicScenarioDefinition scenarioDefinition;
        private readonly INavigationPlanner planner;
        private readonly IExperimentLogSink logSink;
        private readonly bool ownsLogSink;
        private long requestSequence;
        private int nextScheduledChangeIndex;
        private Exception lastError;

        public ExperimentRunnerState State { get; private set; }
        public long CurrentSimulationTick { get; private set; }
        public ResolvedDeterministicScenario Scenario { get; private set; }
        public ResearchNavigationGrid Grid { get; private set; }
        public NavigationOperationMetrics InitializationMetrics { get; private set; }
        public Exception LastError { get { return lastError; } }

        public ExperimentRunner(
            string runId,
            DeterministicScenarioDefinition scenarioDefinition,
            INavigationPlanner planner,
            IExperimentLogSink logSink = null,
            bool ownsLogSink = false)
        {
            if (string.IsNullOrWhiteSpace(runId)) throw new ArgumentException("Run id is required.", "runId");
            this.scenarioDefinition = scenarioDefinition ?? throw new ArgumentNullException("scenarioDefinition");
            this.planner = planner ?? throw new ArgumentNullException("planner");
            this.runId = runId;
            this.logSink = logSink;
            this.ownsLogSink = ownsLogSink;
            State = ExperimentRunnerState.Created;
            CurrentSimulationTick = -1;
        }

        public void Initialize()
        {
            EnsureState(ExperimentRunnerState.Created);
            try
            {
                Scenario = scenarioDefinition.Resolve();
                Grid = Scenario.CreateGrid();
                NavigationPlannerInitialization initialization = new NavigationPlannerInitialization
                {
                    runId = runId,
                    goalSetId = Scenario.GoalSetId,
                    goals = CopyGoals(Scenario.Goals),
                    connectivity = Scenario.Connectivity,
                    allowDiagonalCornerCutting = Scenario.AllowDiagonalCornerCutting,
                    budgetMilliseconds = Scenario.InitializationBudgetMilliseconds
                };

                InitializationMetrics = planner.Initialize(Grid, initialization) ?? new NavigationOperationMetrics();
                EnsurePlannerVersionMatchesGrid("initialize");
                State = ExperimentRunnerState.Initialized;
                LogLifecycle("initialized", string.Empty);
                LogPlannerOperation(
                    "initialize",
                    -1,
                    Grid.Version,
                    Scenario.InitializationBudgetMilliseconds,
                    InitializationMetrics,
                    !InitializationMetrics.budgetExceeded,
                    InitializationMetrics.budgetExceeded ? NavigationFailureReason.PlanningBudgetExceeded.ToString() : string.Empty);
            }
            catch (Exception exception)
            {
                Fault(exception);
                throw;
            }
        }

        public void Begin()
        {
            EnsureState(ExperimentRunnerState.Initialized);
            try
            {
                State = ExperimentRunnerState.Running;
                CurrentSimulationTick = -1;
                nextScheduledChangeIndex = 0;
                LogLifecycle("running", string.Empty);
            }
            catch (Exception exception)
            {
                Fault(exception);
                throw;
            }
        }

        public IReadOnlyList<ExperimentRepairObservation> AdvanceOneTick()
        {
            EnsureState(ExperimentRunnerState.Running);
            if (CurrentSimulationTick + 1 >= Scenario.MaxSimulationTicks)
            {
                throw new InvalidOperationException("The scenario has reached maxSimulationTicks. Complete the run before advancing again.");
            }

            return AdvanceToTick(CurrentSimulationTick + 1);
        }

        public IReadOnlyList<ExperimentRepairObservation> AdvanceToTick(long targetSimulationTick)
        {
            EnsureState(ExperimentRunnerState.Running);
            if (targetSimulationTick <= CurrentSimulationTick)
            {
                throw new ArgumentOutOfRangeException("targetSimulationTick", "Target tick must be greater than the current simulation tick.");
            }
            if (targetSimulationTick >= Scenario.MaxSimulationTicks)
            {
                throw new ArgumentOutOfRangeException("targetSimulationTick", "Target tick must be less than maxSimulationTicks.");
            }

            try
            {
                List<ExperimentRepairObservation> observations = new List<ExperimentRepairObservation>();
                while (nextScheduledChangeIndex < Scenario.ScheduledChanges.Count)
                {
                    ResolvedScheduledNavigationChange scheduled = Scenario.ScheduledChanges[nextScheduledChangeIndex];
                    if (scheduled.SimulationTick > targetSimulationTick) break;
                    if (scheduled.SimulationTick < CurrentSimulationTick)
                    {
                        throw new InvalidOperationException("A scheduled event was skipped: " + scheduled.EventId);
                    }

                    CurrentSimulationTick = scheduled.SimulationTick;
                    NavigationChangeSet changeSet = Grid.ApplyChanges(scheduled.EventId, Grid.Version, scheduled.Changes);
                    NavigationRepairResult repairResult = planner.ApplyChanges(changeSet, scheduled.RepairBudgetMilliseconds);
                    if (repairResult == null) throw new InvalidOperationException("Planner returned a null repair result.");
                    EnsurePlannerVersionMatchesGrid("repair " + scheduled.EventId);
                    if (repairResult.GridVersion != Grid.Version)
                    {
                        throw new InvalidOperationException("Repair result grid version does not match the research grid.");
                    }

                    LogPlannerOperation(
                        "repair",
                        -1,
                        repairResult.GridVersion,
                        scheduled.RepairBudgetMilliseconds,
                        repairResult.Metrics,
                        repairResult.Status == NavigationPlanStatus.Succeeded,
                        repairResult.FailureReason.ToString());
                    observations.Add(new ExperimentRepairObservation(scheduled.EventId, CurrentSimulationTick, changeSet, repairResult));
                    nextScheduledChangeIndex++;
                }
                CurrentSimulationTick = targetSimulationTick;
                return new ReadOnlyCollection<ExperimentRepairObservation>(observations);
            }
            catch (Exception exception)
            {
                Fault(exception);
                throw;
            }
        }

        public NavigationPlanResult PlanForAgent(int agentId, GridCoordinate currentStart)
        {
            return PlanForAgent(agentId, currentStart, null, 0d);
        }

        public NavigationPlanResult PlanForAgent(int agentId, GridCoordinate currentStart, string requestId, double budgetMilliseconds)
        {
            EnsureState(ExperimentRunnerState.Running);
            try
            {
                ResolvedScenarioAgent agent = Scenario.GetAgent(agentId);
                if (!Grid.Contains(currentStart)) throw new ArgumentOutOfRangeException("currentStart", "Current start is outside the research grid.");
                if (!Grid.IsWalkable(currentStart)) throw new ArgumentException("Current start must be walkable.", "currentStart");

                double effectiveBudget = budgetMilliseconds > 0d ? budgetMilliseconds : Scenario.DefaultPlanBudgetMilliseconds;
                if (double.IsNaN(effectiveBudget) || double.IsInfinity(effectiveBudget) || effectiveBudget <= 0d)
                {
                    throw new ArgumentOutOfRangeException("budgetMilliseconds");
                }

                string effectiveRequestId = string.IsNullOrWhiteSpace(requestId)
                    ? string.Format("{0}-plan-{1}", runId, requestSequence++)
                    : requestId;

                NavigationPlanRequest request = new NavigationPlanRequest
                {
                    runId = runId,
                    requestId = effectiveRequestId,
                    goalSetId = Scenario.GoalSetId,
                    agentId = agentId,
                    start = currentStart,
                    goal = agent.Goal,
                    expectedGridVersion = Grid.Version,
                    budgetMilliseconds = effectiveBudget
                };

                NavigationPlanResult result = planner.Plan(request);
                if (result == null) throw new InvalidOperationException("Planner returned a null plan result.");
                EnsurePlannerVersionMatchesGrid("plan " + effectiveRequestId);
                if (result.GridVersion != Grid.Version)
                {
                    throw new InvalidOperationException("Plan result grid version does not match the research grid.");
                }

                LogPlannerOperation(
                    "plan",
                    agentId,
                    result.GridVersion,
                    effectiveBudget,
                    result.Metrics,
                    result.Status == NavigationPlanStatus.Succeeded,
                    result.FailureReason.ToString());
                return result;
            }
            catch (Exception exception)
            {
                Fault(exception);
                throw;
            }
        }

        public void Complete(string message = null)
        {
            if (State != ExperimentRunnerState.Running && State != ExperimentRunnerState.Initialized)
            {
                throw new InvalidOperationException("Only an initialized or running experiment can complete.");
            }
            try
            {
                State = ExperimentRunnerState.Completed;
                LogLifecycle("completed", message ?? string.Empty);
            }
            catch (Exception exception)
            {
                Fault(exception);
                throw;
            }
        }

        public void Dispose()
        {
            if (State == ExperimentRunnerState.Disposed) return;
            Exception disposeError = null;
            try
            {
                planner.Reset();
            }
            catch (Exception exception)
            {
                disposeError = exception;
            }

            if (ownsLogSink && logSink != null)
            {
                try { logSink.Dispose(); }
                catch (Exception exception)
                {
                    if (disposeError == null) disposeError = exception;
                }
            }

            State = ExperimentRunnerState.Disposed;
            if (disposeError != null)
            {
                lastError = disposeError;
                throw disposeError;
            }
        }

        private void Fault(Exception exception)
        {
            lastError = exception;
            State = ExperimentRunnerState.Faulted;
            try { LogLifecycle("faulted", exception.Message); }
            catch { }
        }

        private void EnsureState(ExperimentRunnerState expected)
        {
            if (State != expected)
            {
                throw new InvalidOperationException(string.Format("Experiment runner must be in state {0}, but is {1}.", expected, State));
            }
        }

        private void EnsurePlannerVersionMatchesGrid(string operation)
        {
            if (planner.GridVersion != Grid.Version)
            {
                throw new InvalidOperationException(string.Format(
                    "Planner/grid version mismatch after {0}: planner={1}, grid={2}.",
                    operation,
                    planner.GridVersion,
                    Grid.Version));
            }
        }

        private void LogLifecycle(string state, string message)
        {
            if (logSink == null) return;
            logSink.Enqueue("runner_lifecycle", runId, new ExperimentRunnerLifecycleRecord
            {
                scenarioId = Scenario == null ? scenarioDefinition.scenarioId : Scenario.ScenarioId,
                scenarioFingerprintSha256 = Scenario == null ? string.Empty : Scenario.FingerprintSha256,
                algorithmId = planner.AlgorithmId,
                state = state,
                simulationTick = CurrentSimulationTick,
                message = message ?? string.Empty
            });
        }

        private void LogPlannerOperation(
            string operation,
            int agentId,
            long gridVersion,
            double budgetMilliseconds,
            NavigationOperationMetrics metrics,
            bool succeeded,
            string failureCode)
        {
            if (logSink == null) return;
            NavigationOperationMetrics safeMetrics = metrics ?? new NavigationOperationMetrics();
            logSink.Enqueue("planner_operation", runId, new PlannerOperationRecord
            {
                algorithmId = planner.AlgorithmId,
                operation = operation,
                agentId = agentId,
                gridVersion = gridVersion,
                elapsedCpuMilliseconds = safeMetrics.elapsedCpuMilliseconds,
                processedNodesOrCells = safeMetrics.processedNodesOrCells,
                expandedNodes = safeMetrics.expandedNodes,
                relaxedEdges = safeMetrics.relaxedEdges,
                repairedCells = safeMetrics.repairedCells,
                managedAllocatedBytes = safeMetrics.managedAllocatedBytes,
                budgetMilliseconds = budgetMilliseconds,
                budgetExceeded = safeMetrics.budgetExceeded,
                succeeded = succeeded,
                failureCode = failureCode ?? string.Empty
            });
        }

        private static GridCoordinate[] CopyGoals(IReadOnlyList<GridCoordinate> goals)
        {
            GridCoordinate[] copy = new GridCoordinate[goals.Count];
            for (int index = 0; index < goals.Count; index++) copy[index] = goals[index];
            return copy;
        }
    }
}

using System;
using System.Collections;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Security.Cryptography;
using System.Text;
using DDM.Research.Algorithms;
using DDM.Research.Gate14Re.V1;
using DDM.Research.Gate14ReTB2.V1;
using DDM.Research.Grid;
using DDM.Research.Navigation;
using DDM.Research.Scenarios;
using UnityEngine;
using UnityEngine.AI;

namespace DDM.Research.Gate14ReTB2.V2
{
    /// <summary>
    /// One complete anonymous four-lane superblock per fresh process.  Every lane
    /// is rebuilt from the immutable bundle after Unity has completed destruction
    /// of the preceding lane's runtime objects.  No production identity is ever
    /// written to output, traces, object names, or validation markers.
    /// </summary>
    public sealed class Gate14ReTB2FormalControllerV2 : MonoBehaviour
    {
        private enum RuntimePhase { None, Validation, Warmup, Measuring, Resetting, Finished }

        private const int FrameIntervalCapacity = 1000000;
        public GameObject unitVisualPrefab;

        private readonly List<GameObject> unitObjects = new List<GameObject>();
        private readonly List<UnityEngine.Object> destroyedLaneObjects = new List<UnityEngine.Object>();
        private readonly List<Gate14ReTB2LaneOutputV2> completedLanes = new List<Gate14ReTB2LaneOutputV2>();
        private readonly List<Gate14ReTB2HardResetReceiptV2> resetReceipts = new List<Gate14ReTB2HardResetReceiptV2>();

        private RuntimePhase phase;
        private bool finishing;
        private bool collectionStarted;
        private bool movementEnded;
        private string mode;
        private string projectRoot;
        private string outputPath;
        private string traceDirectory;
        private string measuredRoot;
        private string planSha256;
        private string executionContractSha256;
        private string outputSchemaContractSha256;
        private string executableSha256;
        private string assemblyCSharpSha256;
        private string buildReceiptSha256;
        private string buildTreeSha256;
        private string authorizationId;
        private int wholeSuperblockAttempt;
        private int laneIndex;
        private int validatedLaneCount;
        private Gate14ReTB2FormalSuperblockV2 superblock;
        private Gate14ReTB2InputBundleV1 bundle;
        private LoadedDeterministicScenario loadedScenario;
        private string[] productionPlannerIdsInOrder;

        private Gate14ReTB2PreparedScenarioV1 prepared;
        private Gate14ReMovementKernelV1 kernel;
        private IReadOnlyList<Gate14ReUnitStateV1> states;
        private Gate14ReTextureVisualGridV1 textureVisual;
        private Gate14ReTB2TraceRecorderV1 traceRecorder;
        private GameObject unitRoot;
        private GameObject gridSurface;
        private long[] arrivalTicks;
        private double[] frameIntervals;
        private int frameIntervalCount;
        private int warmupFrames;
        private long previousFrameTimestamp;
        private long lastTraceTick = -1L;

        private void Start()
        {
            byte[] plaintext = null;
            try
            {
                Dictionary<string, string> arguments = ParseArguments(Environment.GetCommandLineArgs());
                mode = Required(arguments, "gate14re-tb2-mode");
                if (mode != "validation" && mode != "formal") throw new InvalidOperationException("Runner mode must be validation or formal.");
                projectRoot = Path.GetFullPath(Required(arguments, "gate14re-tb2-project-root"));
                string planPath = Path.GetFullPath(Required(arguments, "gate14re-tb2-plan"));
                planSha256 = RequiredLowerSha(arguments, "gate14re-tb2-plan-sha256");
                string contractPath = Path.GetFullPath(Required(arguments, "gate14re-tb2-execution-contract"));
                executionContractSha256 = RequiredLowerSha(arguments, "gate14re-tb2-execution-contract-sha256");
                string outputSchemaPath = Path.GetFullPath(Required(arguments, "gate14re-tb2-output-schema-contract"));
                outputSchemaContractSha256 = RequiredLowerSha(arguments, "gate14re-tb2-output-schema-contract-sha256");
                string commitmentPath = Path.GetFullPath(Required(arguments, "gate14re-tb2-custody-commitment"));
                string commitmentSha256 = RequiredLowerSha(arguments, "gate14re-tb2-custody-commitment-sha256");
                string superblockId = Required(arguments, "gate14re-tb2-superblock-id");
                outputPath = Path.GetFullPath(Required(arguments, "gate14re-tb2-output"));
                traceDirectory = Path.GetFullPath(Required(arguments, "gate14re-tb2-trace-directory"));
                buildTreeSha256 = RequiredLowerSha(arguments, "gate14re-tb2-build-tree-sha256");

                RequireReadOnlyFile(planPath, planSha256);
                RequireReadOnlyFile(contractPath, executionContractSha256);
                RequireReadOnlyFile(outputSchemaPath, outputSchemaContractSha256);
                RequireReadOnlyFile(commitmentPath, commitmentSha256);
                Gate14ReTB2FormalPlanV2 plan = JsonUtility.FromJson<Gate14ReTB2FormalPlanV2>(File.ReadAllText(planPath, Encoding.UTF8));
                Gate14ReTB2ExecutionContractV2 contract = JsonUtility.FromJson<Gate14ReTB2ExecutionContractV2>(File.ReadAllText(contractPath, Encoding.UTF8));
                Gate14ReTB2LabelCustodyCommitmentV1 commitment = JsonUtility.FromJson<Gate14ReTB2LabelCustodyCommitmentV1>(File.ReadAllText(commitmentPath, Encoding.UTF8));
                ValidatePlan(plan);
                ValidateContract(contract, plan, planSha256, commitmentSha256);
                ValidateCommitment(commitment);
                superblock = FindSuperblock(plan, superblockId);
                ValidateSuperblock(superblock);

                executableSha256 = Sha256File(GetCurrentExecutablePath());
                assemblyCSharpSha256 = Sha256File(GetCurrentAssemblyPath());
                buildReceiptSha256 = Sha256File(GetAdjacentBuildReceiptPath());
                if (mode == "formal")
                {
                    wholeSuperblockAttempt = ParseAttempt(Required(arguments, "gate14re-tb2-whole-superblock-attempt"));
                    ValidateFormalAuthorization(arguments);
                    collectionStarted = true;
                }
                else
                {
                    wholeSuperblockAttempt = 0;
                    string verificationRoot = Path.GetFullPath(Path.Combine(projectRoot, "Research", "Verification", "Gate14Re-TB2"));
                    RequireContained(outputPath, verificationRoot, "Validation output");
                    RequireContained(traceDirectory, verificationRoot, "Validation trace directory");
                    Directory.CreateDirectory(Path.GetDirectoryName(outputPath));
                    Directory.CreateDirectory(traceDirectory);
                }

                string bundlePath = Path.GetFullPath(Path.Combine(projectRoot, superblock.bundleRelativePath.Replace('/', Path.DirectorySeparatorChar)));
                RequireContained(bundlePath, Path.Combine(projectRoot, "Research", "Gate14Re-TB2", "Execution", "v1", "input-bundles"), "Adopted input bundle");
                RequireReadOnlyFile(bundlePath, superblock.bundleFileSha256);
                if (new FileInfo(bundlePath).Length != superblock.bundleFileBytes) throw new InvalidOperationException("Input bundle byte count mismatch.");
                bundle = JsonUtility.FromJson<Gate14ReTB2InputBundleV1>(File.ReadAllText(bundlePath, Encoding.UTF8));
                ValidateBundleBinding(bundle, superblock);

                string scenarioPath = Path.GetFullPath(Path.Combine(projectRoot, bundle.sourceScenarioRelativePath.Replace('/', Path.DirectorySeparatorChar)));
                if (!File.Exists(scenarioPath) || Sha256File(scenarioPath) != bundle.sourceScenarioSha256) throw new InvalidOperationException("Source scenario binding failed.");
                loadedScenario = DeterministicScenarioJson.LoadFromFile(scenarioPath);

                if (mode == "formal")
                {
                    string payloadPath = Path.GetFullPath(Path.Combine(projectRoot, commitment.protection.payloadRelativePath.Replace('/', Path.DirectorySeparatorChar)));
                    string entropyPath = Path.GetFullPath(Path.Combine(projectRoot, commitment.protection.entropyRelativePath.Replace('/', Path.DirectorySeparatorChar)));
                    RequireReadOnlyFile(payloadPath, commitment.protection.payloadSha256);
                    RequireReadOnlyFile(entropyPath, commitment.protection.entropySha256);
                    byte[] entropy = File.ReadAllBytes(entropyPath);
                    try { plaintext = Gate14ReTB2DpapiV1.UnprotectCurrentUserNoUi(File.ReadAllBytes(payloadPath), entropy); }
                    finally { Array.Clear(entropy, 0, entropy.Length); }
                    if (Sha256Bytes(plaintext) != commitment.mappingCommitmentSha256) throw new InvalidOperationException("Label custody plaintext commitment mismatch.");
                    Gate14ReTB2LabelCustodySecretV1 secret = JsonUtility.FromJson<Gate14ReTB2LabelCustodySecretV1>(Encoding.UTF8.GetString(plaintext));
                    productionPlannerIdsInOrder = ResolveAllAnonymousLabels(secret, commitment, superblock.anonymousLabelsInOrder);
                    Array.Clear(plaintext, 0, plaintext.Length);
                    plaintext = null;
                }
                else
                {
                    // Validation deliberately exercises all four planners without reading custody.
                    productionPlannerIdsInOrder = new[]
                    {
                        NavigationAlgorithmIds.AStarRepeated,
                        NavigationAlgorithmIds.DStarLite,
                        NavigationAlgorithmIds.CorrectedFullRecomputeFlowField,
                        NavigationAlgorithmIds.IncrementalDynamicFlowField
                    };
                }

                ConfigureEnvironment();
                Gate14ReTB2PreparedScenarioV1 cameraScenario = Gate14ReTB2ProtocolV1.Prepare(loadedScenario, bundle);
                ConfigureCamera(cameraScenario.Resolved);
                laneIndex = 0;
                PrepareCurrentLane();
            }
            catch (Exception exception)
            {
                if (plaintext != null) Array.Clear(plaintext, 0, plaintext.Length);
                FinishFailure(exception);
            }
        }

        private void Update()
        {
            if (finishing || kernel == null || phase != RuntimePhase.Validation) return;
            try
            {
                int guard = 0;
                while (kernel.CurrentTick < 10L && guard++ < 32)
                {
                    kernel.AdvanceOneFixedTick();
                    CaptureArrivalTicks();
                    CaptureTraceAtRegisteredTick();
                }
                UpdateUnitVisualPositions();
                if (kernel.CurrentTick != 10L || kernel.StructuralEventRecords.Count != 2 || kernel.GridVersion != kernel.PlannerGridVersion || textureVisual.VisualRevision != kernel.GridVersion)
                    throw new InvalidOperationException("Validation did not apply the first ordered event pair in grid/planner/visual lockstep.");
                validatedLaneCount++;
                if (laneIndex + 1 < 4) StartCoroutine(ResetAndBeginNextLane());
                else CompleteValidation();
            }
            catch (Exception exception) { FinishFailure(exception); }
        }

        private void FixedUpdate()
        {
            if (finishing || kernel == null || phase != RuntimePhase.Measuring || movementEnded) return;
            try
            {
                if (!AllUnitsTerminal() && kernel.CurrentTick + 1L < Gate14ReTB2ProtocolV1.MovementCapTicks)
                {
                    kernel.AdvanceOneFixedTick();
                    CaptureArrivalTicks();
                    UpdateUnitVisualPositions();
                    CaptureTraceAtRegisteredTick();
                }
                movementEnded = AllUnitsTerminal() || kernel.CurrentTick + 1L >= Gate14ReTB2ProtocolV1.MovementCapTicks;
                if (movementEnded && superblock.traceCaptureRequired && kernel.CurrentTick >= 0L && lastTraceTick != kernel.CurrentTick)
                {
                    traceRecorder.Capture(kernel.CurrentTick, kernel.GridVersion, kernel.StructuralEventRecords.Count);
                    lastTraceTick = kernel.CurrentTick;
                }
            }
            catch (Exception exception) { FinishFailure(exception); }
        }

        private void LateUpdate()
        {
            if (finishing || kernel == null) return;
            try
            {
                if (phase == RuntimePhase.Warmup)
                {
                    warmupFrames++;
                    if (warmupFrames >= Gate14ReTB2ProtocolV1.WarmupRenderedFrames)
                    {
                        kernel.Release();
                        previousFrameTimestamp = Stopwatch.GetTimestamp();
                        phase = RuntimePhase.Measuring;
                    }
                    return;
                }
                if (phase != RuntimePhase.Measuring) return;
                long now = Stopwatch.GetTimestamp();
                double interval = (double)(now - previousFrameTimestamp) / Stopwatch.Frequency;
                previousFrameTimestamp = now;
                if (interval <= 0d || double.IsNaN(interval) || double.IsInfinity(interval)) throw new InvalidOperationException("Rendered frame interval is non-positive or non-finite.");
                if (frameIntervalCount >= frameIntervals.Length) throw new InvalidOperationException("Preallocated rendered-frame interval capacity was exceeded.");
                frameIntervals[frameIntervalCount++] = interval;
                if (movementEnded) CompleteMeasuredLane();
            }
            catch (Exception exception) { FinishFailure(exception); }
        }

        private void PrepareCurrentLane()
        {
            if (laneIndex < 0 || laneIndex >= 4) throw new InvalidOperationException("Lane index is outside the frozen four-lane order.");
            prepared = Gate14ReTB2ProtocolV1.Prepare(loadedScenario, bundle);
            gridSurface = CreateGridSurface(prepared.Resolved);
            textureVisual = new Gate14ReTextureVisualGridV1(gridSurface.GetComponent<Renderer>());
            InstantiateUnitVisuals(prepared.Resolved);
            string laneId = superblock.laneIdsInOrder[laneIndex];
            kernel = new Gate14ReMovementKernelV1(laneId, prepared.Resolved, CreatePlanner(productionPlannerIdsInOrder[laneIndex]), textureVisual);
            states = kernel.Units;
            arrivalTicks = new long[states.Count];
            for (int index = 0; index < arrivalTicks.Length; index++) arrivalTicks[index] = -1L;
            frameIntervals = mode == "formal" ? new double[FrameIntervalCapacity] : null;
            frameIntervalCount = 0;
            warmupFrames = 0;
            movementEnded = false;
            previousFrameTimestamp = 0L;
            lastTraceTick = -1L;
            traceRecorder = superblock.traceCaptureRequired ? new Gate14ReTB2TraceRecorderV1(CreateTraceHeader(), states) : null;
            UpdateUnitVisualPositions();
            if (mode == "validation")
            {
                kernel.Release();
                phase = RuntimePhase.Validation;
            }
            else
            {
                phase = RuntimePhase.Warmup;
            }
        }

        private void CompleteMeasuredLane()
        {
            if (mode != "formal" || !collectionStarted) throw new InvalidOperationException("Formal output is forbidden without an authorized collection.");
            CaptureArrivalTicks();
            Gate14ReTB2TraceWriteResultV1 trace = null;
            string relativeTrace = null;
            if (superblock.traceCaptureRequired)
            {
                if (traceRecorder == null || traceRecorder.CapturedCount < 1) throw new InvalidOperationException("Frozen trace-audit lane captured no trace frame.");
                string tracePath = GetCurrentTracePath();
                trace = traceRecorder.Flush(tracePath);
                relativeTrace = Forward(Path.GetRelativePath(measuredRoot, tracePath));
            }
            else if (traceRecorder != null)
            {
                throw new InvalidOperationException("Non-audit lane unexpectedly allocated a trace recorder.");
            }

            Gate14ReTB2UnitRawV1[] units = new Gate14ReTB2UnitRawV1[states.Count];
            int arrivedCount = 0, activeCount = 0, noPathCount = 0, budgetCount = 0, invalidCount = 0, internalCount = 0;
            List<string> critical = new List<string>();
            HashSet<int> identities = new HashSet<int>();
            for (int index = 0; index < states.Count; index++)
            {
                Gate14ReUnitStateV1 state = states[index];
                if (!identities.Add(state.AgentId)) critical.Add("duplicate_unit_identity:" + state.AgentId.ToString(CultureInfo.InvariantCulture));
                switch (state.State)
                {
                    case Gate14ReUnitTerminalStateV1.Arrived: arrivedCount++; break;
                    case Gate14ReUnitTerminalStateV1.Active: activeCount++; break;
                    case Gate14ReUnitTerminalStateV1.NoPath: noPathCount++; break;
                    case Gate14ReUnitTerminalStateV1.BudgetExceeded: budgetCount++; break;
                    case Gate14ReUnitTerminalStateV1.InvalidPlan: invalidCount++; critical.Add("illegal_or_invalid_plan:" + state.AgentId.ToString(CultureInfo.InvariantCulture)); break;
                    case Gate14ReUnitTerminalStateV1.InternalFailure: internalCount++; break;
                }
                if (!IsFinite(state.Position)) critical.Add("nonfinite_position:" + state.AgentId.ToString(CultureInfo.InvariantCulture));
                if (state.State == Gate14ReUnitTerminalStateV1.Arrived && (!state.CurrentCell.Equals(state.Goal) || arrivalTicks[index] < 0L))
                    critical.Add("wrong_goal_completion:" + state.AgentId.ToString(CultureInfo.InvariantCulture));
                if (double.IsNaN(state.CumulativeHorizontalPathLength) || double.IsInfinity(state.CumulativeHorizontalPathLength) || state.CumulativeHorizontalPathLength < 0d)
                    critical.Add("invalid_path_length:" + state.AgentId.ToString(CultureInfo.InvariantCulture));
                units[index] = new Gate14ReTB2UnitRawV1
                {
                    unitIndex = state.AgentId,
                    terminalState = state.State.ToString(),
                    arrived = state.State == Gate14ReUnitTerminalStateV1.Arrived,
                    arrivalTick = arrivalTicks[index],
                    cumulativeHorizontalPathLength = state.CumulativeHorizontalPathLength
                };
            }
            if (identities.Count != bundle.unitCount) critical.Add("missing_unit_identity");
            double[] rawIntervals = new double[frameIntervalCount];
            Array.Copy(frameIntervals, rawIntervals, frameIntervalCount);
            double median, p95;
            SummarizeFrameIntervals(rawIntervals, out median, out p95);
            if (CountUnitsWithEnabledRenderer() != bundle.unitCount) throw new InvalidOperationException("Full-population renderer cardinality changed during measurement.");

            completedLanes.Add(new Gate14ReTB2LaneOutputV2
            {
                laneId = superblock.laneIdsInOrder[laneIndex],
                anonymousAlgorithmLabel = superblock.anonymousLabelsInOrder[laneIndex],
                orderPosition = laneIndex + 1,
                allUnitsArrived = arrivedCount == states.Count,
                arrivedCount = arrivedCount,
                activeAtCapCount = activeCount,
                noPathCount = noPathCount,
                budgetExceededCount = budgetCount,
                invalidPlanCount = invalidCount,
                internalFailureCount = internalCount,
                m1Seconds = arrivedCount == states.Count ? Math.Max(0d, (kernel.CurrentTick + 1L) * Gate14ReTB2ProtocolV1.FixedStepSeconds) : Gate14ReTB2ProtocolV1.MovementCapSeconds,
                units = units,
                m2CommonMaskMeanPathLength = 0d,
                m5CriticalViolationCount = critical.Count,
                m5CriticalViolationCodes = critical.ToArray(),
                measuredRenderedFrameIntervals = rawIntervals.Length,
                frameIntervalsSeconds = rawIntervals,
                medianFrameTimeSeconds = median,
                nearestRankP95FrameTimeSeconds = p95,
                simulationTickAtEnd = kernel.CurrentTick,
                structuralEventCount = kernel.StructuralEventRecords.Count,
                structuralEvents = CopyEvents(kernel.StructuralEventRecords),
                traceCaptured = superblock.traceCaptureRequired,
                traceRawRelativePath = relativeTrace,
                traceRawSha256 = trace == null ? null : trace.traceRawSha256,
                traceMerkleRootSha256 = trace == null ? null : trace.traceMerkleRootSha256,
                traceChunkCount = trace == null ? 0 : trace.traceChunkCount,
                traceCapturedTickCount = trace == null ? 0 : trace.traceCapturedTickCount,
                traceCompressionPending = trace != null,
                complete = true
            });

            if (laneIndex + 1 < 4) StartCoroutine(ResetAndBeginNextLane());
            else CompleteFormalSuperblock();
        }

        private IEnumerator ResetAndBeginNextLane()
        {
            phase = RuntimePhase.Resetting;
            int finishedPosition = laneIndex + 1;
            QueueLaneObjectsForDestruction();
            yield return null;
            yield return new WaitForEndOfFrame();
            int live = 0;
            for (int index = 0; index < destroyedLaneObjects.Count; index++) if (destroyedLaneObjects[index] != null) live++;
            if (live != 0)
            {
                FinishFailure(new InvalidOperationException("Prior-lane Unity runtime objects survived the hard-reset destruction barrier."));
                yield break;
            }
            try
            {
                laneIndex++;
                PrepareCurrentLane();
                resetReceipts.Add(new Gate14ReTB2HardResetReceiptV2
                {
                    afterOrderPosition = finishedPosition,
                    destroyCompleted = true,
                    priorLaneRuntimeObjectCount = live,
                    nextLanePreparedFromImmutableBundle = true,
                    passed = true
                });
            }
            catch (Exception exception) { FinishFailure(exception); }
        }

        private void QueueLaneObjectsForDestruction()
        {
            destroyedLaneObjects.Clear();
            if (unitRoot != null)
            {
                destroyedLaneObjects.Add(unitRoot);
                for (int index = 0; index < unitObjects.Count; index++) if (unitObjects[index] != null) destroyedLaneObjects.Add(unitObjects[index]);
                Destroy(unitRoot);
            }
            if (gridSurface != null)
            {
                Renderer renderer = gridSurface.GetComponent<Renderer>();
                if (renderer != null && renderer.sharedMaterial != null) destroyedLaneObjects.Add(renderer.sharedMaterial);
                if (textureVisual != null && textureVisual.Texture != null) destroyedLaneObjects.Add(textureVisual.Texture);
                destroyedLaneObjects.Add(gridSurface);
            }
            if (textureVisual != null) textureVisual.Dispose();
            if (gridSurface != null) Destroy(gridSurface);
            unitObjects.Clear();
            unitRoot = null;
            gridSurface = null;
            textureVisual = null;
            traceRecorder = null;
            kernel = null;
            states = null;
            arrivalTicks = null;
            frameIntervals = null;
            prepared = null;
        }

        private void CompleteFormalSuperblock()
        {
            if (completedLanes.Count != 4 || resetReceipts.Count != 3) throw new InvalidOperationException("Whole-superblock completeness/reset cardinality failed.");
            int[] commonMask = BuildCommonM2Mask(completedLanes, bundle.unitCount);
            int minimum = Math.Max(1, (int)Math.Ceiling(0.8d * bundle.unitCount));
            if (commonMask.Length < minimum) throw new InvalidOperationException("Common M2 mask is below the pre-registered 80 percent minimum.");
            for (int lane = 0; lane < completedLanes.Count; lane++)
            {
                double total = 0d;
                for (int mask = 0; mask < commonMask.Length; mask++) total += FindUnit(completedLanes[lane].units, commonMask[mask]).cumulativeHorizontalPathLength;
                completedLanes[lane].m2CommonMaskMeanPathLength = total / commonMask.Length;
            }

            Gate14ReTB2SuperblockOutputV2 output = new Gate14ReTB2SuperblockOutputV2
            {
                schema = "gate14re-tb2-anonymous-superblock-output-v2",
                studyId = "Gate14Re-TB2",
                status = "COMPLETE",
                stage = "FORMAL_CONFIRMATORY_R2",
                superblockId = superblock.superblockId,
                operationalChunkId = superblock.operationalChunkId,
                module = bundle.module,
                conditionId = bundle.conditionId,
                unitCount = bundle.unitCount,
                drawIndex = bundle.drawIndex,
                distanceStratum = bundle.distanceStratum,
                bundleSha256 = bundle.bundleSha256,
                bundleFileSha256 = superblock.bundleFileSha256,
                sourceScenarioSha256 = bundle.sourceScenarioSha256,
                planSha256 = planSha256,
                executionContractSha256 = executionContractSha256,
                outputSchemaContractSha256 = outputSchemaContractSha256,
                executableSha256 = executableSha256,
                assemblyCSharpSha256 = assemblyCSharpSha256,
                buildReceiptSha256 = buildReceiptSha256,
                authorizationId = authorizationId,
                anonymousLabelsInOrder = (string[])superblock.anonymousLabelsInOrder.Clone(),
                lanes = completedLanes.ToArray(),
                commonM2MaskUnitIndices = commonMask,
                commonM2MaskCount = commonMask.Length,
                commonM2MaskMinimumRequired = minimum,
                traceCaptureRequired = superblock.traceCaptureRequired,
                hardResetReceipts = resetReceipts.ToArray(),
                warmupRenderedFramesPerLane = Gate14ReTB2ProtocolV1.WarmupRenderedFrames,
                wholeSuperblockAttempt = wholeSuperblockAttempt,
                productionAlgorithmIdentityPresent = false,
                complete = true,
                formalObservationProduced = true
            };
            WriteAtomicJson(outputPath, output, false);
            productionPlannerIdsInOrder = null;
            FinishAndQuit(0);
        }

        private void CompleteValidation()
        {
            if (validatedLaneCount != 4 || resetReceipts.Count != 3) throw new InvalidOperationException("Validation did not exercise four lanes and three hard resets.");
            Gate14ReTB2ValidationMarkerV2 marker = new Gate14ReTB2ValidationMarkerV2
            {
                schema = "gate14re-tb2-runner-validation-marker-v2",
                studyId = "Gate14Re-TB2",
                status = "PASS",
                superblockId = superblock.superblockId,
                validatedAnonymousLanes = validatedLaneCount,
                validatedHardResets = resetReceipts.Count,
                allFourProductionPlannersExercisedWithoutCustodyDecryption = true,
                inputBundlePreparedPerLane = true,
                labelCustodyResolvedInMemory = false,
                productionIdentityWritten = false,
                tracePolicyMatchedPlan = traceRecorder != null == superblock.traceCaptureRequired,
                formalObservationProduced = false,
                m1ThroughM5OutputProduced = false,
                collectionStarted = false
            };
            WriteAtomicJson(outputPath, marker, true);
            productionPlannerIdsInOrder = null;
            FinishAndQuit(0);
        }

        private static int[] BuildCommonM2Mask(List<Gate14ReTB2LaneOutputV2> lanes, int unitCount)
        {
            List<int> result = new List<int>();
            for (int unitIndex = 0; unitIndex < unitCount; unitIndex++)
            {
                bool eligible = true;
                for (int lane = 0; lane < lanes.Count; lane++)
                {
                    Gate14ReTB2UnitRawV1 unit = FindUnit(lanes[lane].units, unitIndex);
                    eligible &= unit.arrived && !double.IsNaN(unit.cumulativeHorizontalPathLength) && !double.IsInfinity(unit.cumulativeHorizontalPathLength) && unit.cumulativeHorizontalPathLength >= 0d;
                }
                if (eligible) result.Add(unitIndex);
            }
            return result.ToArray();
        }

        private static Gate14ReTB2UnitRawV1 FindUnit(Gate14ReTB2UnitRawV1[] units, int unitIndex)
        {
            Gate14ReTB2UnitRawV1 found = null;
            for (int index = 0; index < units.Length; index++)
            {
                if (units[index].unitIndex != unitIndex) continue;
                if (found != null) throw new InvalidOperationException("Duplicate unit identity in lane output.");
                found = units[index];
            }
            if (found == null) throw new InvalidOperationException("Common M2 mask unit is absent from a lane.");
            return found;
        }

        private Gate14ReTB2TraceHeaderV1 CreateTraceHeader()
        {
            return new Gate14ReTB2TraceHeaderV1
            {
                schema = "gate14re-tb2-trace-header-v1",
                studyId = "Gate14Re-TB2",
                sampleId = superblock.laneIdsInOrder[laneIndex],
                superblockId = superblock.superblockId,
                anonymousAlgorithmLabel = superblock.anonymousLabelsInOrder[laneIndex],
                conditionId = bundle.conditionId,
                unitCount = bundle.unitCount,
                inputBundleSha256 = bundle.bundleSha256,
                buildTreeSha256 = buildTreeSha256,
                assemblySha256 = assemblyCSharpSha256,
                fixedStepSeconds = Gate14ReTB2ProtocolV1.FixedStepSeconds,
                captureEveryFixedTicks = Gate14ReTB2ProtocolV1.TraceCaptureEveryTicks,
                movementCapTicks = Gate14ReTB2ProtocolV1.MovementCapTicks
            };
        }

        private void CaptureTraceAtRegisteredTick()
        {
            if (!superblock.traceCaptureRequired) return;
            if (traceRecorder == null) throw new InvalidOperationException("Trace-audit lane has no trace recorder.");
            long tick = kernel.CurrentTick;
            if (tick >= 0L && tick % Gate14ReTB2ProtocolV1.TraceCaptureEveryTicks == 0L && tick != lastTraceTick)
            {
                traceRecorder.Capture(tick, kernel.GridVersion, kernel.StructuralEventRecords.Count);
                lastTraceTick = tick;
            }
        }

        private void CaptureArrivalTicks()
        {
            for (int index = 0; index < states.Count; index++)
                if (arrivalTicks[index] < 0L && states[index].State == Gate14ReUnitTerminalStateV1.Arrived) arrivalTicks[index] = kernel.CurrentTick;
        }

        private bool AllUnitsTerminal()
        {
            for (int index = 0; index < states.Count; index++) if (states[index].State == Gate14ReUnitTerminalStateV1.Active) return false;
            return true;
        }

        private string GetCurrentTracePath()
        {
            string path = Path.GetFullPath(Path.Combine(traceDirectory, superblock.laneIdsInOrder[laneIndex] + ".trace.raw"));
            RequireContained(path, traceDirectory, "Formal lane trace");
            if (File.Exists(path) || File.Exists(path + ".tmp")) throw new IOException("Trace overwrite/resume is forbidden.");
            return path;
        }

        private void ValidateFormalAuthorization(Dictionary<string, string> arguments)
        {
            string path = Path.GetFullPath(Required(arguments, "gate14re-tb2-authorization"));
            string sha = RequiredLowerSha(arguments, "gate14re-tb2-authorization-sha256");
            RequireReadOnlyFile(path, sha);
            Gate14ReTB2CollectionAuthorizationV2 authorization = JsonUtility.FromJson<Gate14ReTB2CollectionAuthorizationV2>(File.ReadAllText(path, Encoding.UTF8));
            if (authorization == null || authorization.schema != "gate14re-tb2-collection-authorization-v2" || authorization.studyId != "Gate14Re-TB2" || authorization.status != "AUTHORIZED" || !authorization.userExplicitlyAuthorizedCollection)
                throw new InvalidOperationException("Collection authorization schema/status binding failed.");
            if (authorization.stage != "FORMAL_CONFIRMATORY_R2" || authorization.planSha256 != planSha256 || authorization.executionContractSha256 != executionContractSha256 || authorization.outputSchemaContractSha256 != outputSchemaContractSha256 || authorization.executableSha256 != executableSha256 || authorization.assemblyCSharpSha256 != assemblyCSharpSha256 || authorization.buildReceiptSha256 != buildReceiptSha256)
                throw new InvalidOperationException("Collection authorization does not bind this v2 plan, contracts, executable, assembly, and build receipt.");
            if (string.IsNullOrWhiteSpace(authorization.authorizationId)) throw new InvalidOperationException("Collection authorization id is missing.");
            measuredRoot = Path.GetFullPath(authorization.measuredRoot);
            RequireContained(measuredRoot, Path.Combine(projectRoot, "Research", "FormalRuns", "Gate14Re-TB2", "PhaseA"), "Measured root");
            RequireContained(outputPath, measuredRoot, "Formal superblock output");
            RequireContained(traceDirectory, measuredRoot, "Formal trace directory");
            if (!Directory.Exists(measuredRoot) || !Directory.Exists(Path.GetDirectoryName(outputPath)) || !Directory.Exists(traceDirectory))
                throw new DirectoryNotFoundException("The authorized supervisor must create the measured root, attempt directory, and trace directory before launch.");
            if (File.Exists(outputPath) || File.Exists(outputPath + ".tmp") || File.Exists(outputPath + ".failure.json"))
                throw new IOException("Formal superblock overwrite/resume is forbidden.");
            authorizationId = authorization.authorizationId;
        }

        private static void ValidatePlan(Gate14ReTB2FormalPlanV2 plan)
        {
            if (plan == null || plan.schema != "gate14re-tb2-simplified-formal-execution-plan-v2" || plan.studyId != "Gate14Re-TB2" || plan.version != 2 || plan.status != "FROZEN_NON_EXECUTING_NOT_AUTHORIZED" || plan.stage != "FORMAL_CONFIRMATORY_R2" || plan.route != "R2")
                throw new InvalidOperationException("Anonymous v2 formal plan header is invalid.");
            if (plan.B != 336 || plan.designCellCount != 16 || !plan.quantitySubstudyRetained || !plan.N128AnchorReuse || plan.plannedUniqueSuperblocks != 5376 || plan.plannedAnonymousAlgorithmLanes != 21504 || plan.plannedFreshUnityProcesses != 5376 || plan.processesPerSuperblock != 1 || plan.lanesPerProcess != 4 || plan.operationalChunkCount != 336 || plan.superblocksPerOperationalChunk != 16 || plan.orderPermutationCount != 6 || plan.replicatesPerOrderPerCell != 56 || plan.fullM1ThroughM5TelemetryLanes != 21504 || plan.tracedSuperblocks != 288 || plan.tracedAnonymousLanes != 1152)
                throw new InvalidOperationException("Anonymous v2 formal plan design binding is invalid.");
            if (plan.algorithmIdentityPresent || !plan.wholeSuperblockAtomicity || !plan.oneFreshProcessPerSuperblock || !plan.serialLanesInFrozenWilliamsOrder || !plan.hardResetBetweenLanesRequired || plan.maximumWholeSuperblockTechnicalReplacements != 1 || plan.perAlgorithmRetryResumeTopUpMergeSkipReorder || plan.formalRootCreated || plan.formalCollectionAuthorized)
                throw new InvalidOperationException("Anonymous v2 formal plan isolation/authorization policy is invalid.");
            if (plan.anonymousLabels == null || plan.anonymousLabels.Length != 4 || plan.superblocks == null || plan.superblocks.Length != 5376)
                throw new InvalidOperationException("Anonymous v2 formal plan cardinality is invalid.");
        }

        private static void ValidateContract(Gate14ReTB2ExecutionContractV2 contract, Gate14ReTB2FormalPlanV2 plan, string expectedPlanSha256, string commitmentSha256)
        {
            if (contract == null || contract.schema != "gate14re-tb2-execution-contract-v2" || contract.studyId != "Gate14Re-TB2" || contract.version != 2 || contract.status != "FROZEN_NON_EXECUTING_NOT_AUTHORIZED" || contract.stage != plan.stage)
                throw new InvalidOperationException("V2 execution contract header is invalid.");
            if (contract.route != "R2" || contract.B != 336 || contract.designCellCount != 16 || contract.plannedUniqueSuperblocks != 5376 || contract.plannedAnonymousAlgorithmLanes != 21504 || contract.plannedFreshUnityProcesses != 5376 || contract.formalPlanSha256 != expectedPlanSha256 || contract.inputBundleAdoptionReceiptSha256 != plan.inputBundleAdoptionReceiptSha256 || contract.sourceV1InputBundleManifestSha256 != plan.sourceV1InputBundleManifestSha256 || contract.labelCustodyCommitmentSha256 != commitmentSha256)
                throw new InvalidOperationException("V2 execution contract plan/input/custody binding failed.");
            if (contract.fixedStepSeconds != Gate14ReTB2ProtocolV1.FixedStepSeconds || contract.movementCapSecondsPerLane != Gate14ReTB2ProtocolV1.MovementCapSeconds || contract.preReleaseWarmupRenderedFramesPerLane != Gate14ReTB2ProtocolV1.WarmupRenderedFrames || contract.traceCaptureEveryFixedTicks != Gate14ReTB2ProtocolV1.TraceCaptureEveryTicks)
                throw new InvalidOperationException("V2 execution contract timing binding failed.");
            if (contract.processModel == null || !contract.processModel.oneFreshProcessPerCompleteSuperblock || contract.processModel.processesPerSuperblock != 1 || contract.processModel.anonymousLanesPerProcess != 4 || !contract.processModel.serialWithinSuperblock || !contract.processModel.serialAcrossSuperblocks || !contract.processModel.wholeSuperblockAtomicity || contract.processModel.maximumWholeSuperblockTechnicalReplacements != 1 || contract.processModel.perAlgorithmRetryResumeTopUpMergeSkipReorder || contract.processModel.perProcessHardTimeoutSeconds != 3600 || !contract.processModel.failClosedAfterFailedWholeSuperblockReplacement)
                throw new InvalidOperationException("V2 process model drifted.");
            if (contract.hardResetBetweenLanes == null || !contract.hardResetBetweenLanes.required || !contract.hardResetBetweenLanes.waitForUnityDestroyCompletion || !contract.hardResetBetweenLanes.verifyNoPriorLaneRuntimeObjects || contract.hardResetBetweenLanes.cacheOrOperatingSystemIsolationClaimed)
                throw new InvalidOperationException("V2 hard-reset contract drifted.");
            if (contract.trace == null || !contract.trace.selectionOutcomeIndependent || contract.trace.tracedSuperblocks != 288 || contract.trace.tracedAnonymousLanes != 1152 || contract.trace.untracedAnonymousLanes != 20352 || contract.trace.captureHzWhenSelected != 10 || !contract.trace.essentialM1ThroughM5TelemetryRetainedForEveryLane || !contract.trace.preallocatedDuringMeasuredWindow || contract.trace.fileIoDuringMeasuredWindow || contract.trace.compressionDuringMeasuredWindow || !contract.trace.flushAfterMeasuredWindow || contract.trace.plannerInvokedByReplay)
                throw new InvalidOperationException("V2 trace-audit contract drifted.");
            if (contract.productionIdentityPermittedInOutput || contract.fileIoDuringMeasuredWindow || contract.compressionDuringMeasuredWindow || contract.collectionAuthorized)
                throw new InvalidOperationException("V2 identity/authorization boundary drifted.");
        }

        private static void ValidateCommitment(Gate14ReTB2LabelCustodyCommitmentV1 value)
        {
            if (value == null || value.schema != "gate14re-tb2-label-custody-commitment-v1" || value.studyId != "Gate14Re-TB2" || value.status != "FROZEN_MAPPING_ENCRYPTED_NOT_RELEASED" || value.plaintextMappingPersisted || value.mappingMayBeReleasedBeforeFrozenWinnerAdjudication || value.unblindingAuthorized)
                throw new InvalidOperationException("Label custody commitment header/policy is invalid.");
            if (value.protection == null || value.protection.mechanism != "Windows DPAPI CryptProtectData" || value.protection.scope != "CurrentUser on this host account" || !value.protection.uiForbidden)
                throw new InvalidOperationException("Label custody protection mechanism drifted.");
        }

        private static string[] ResolveAllAnonymousLabels(Gate14ReTB2LabelCustodySecretV1 secret, Gate14ReTB2LabelCustodyCommitmentV1 commitment, string[] requestedOrder)
        {
            if (secret == null || secret.schema != "gate14re-tb2-label-custody-secret-v1" || secret.studyId != "Gate14Re-TB2" || secret.custodyId != commitment.custodyId || secret.mapping == null || secret.mapping.Length != 4)
                throw new InvalidOperationException("Decrypted label custody structure is invalid.");
            Dictionary<string, string> mapping = new Dictionary<string, string>(StringComparer.Ordinal);
            HashSet<string> algorithms = new HashSet<string>(StringComparer.Ordinal);
            for (int index = 0; index < secret.mapping.Length; index++)
            {
                Gate14ReTB2LabelMapEntryV1 entry = secret.mapping[index];
                if (entry == null || mapping.ContainsKey(entry.anonymousLabel) || !algorithms.Add(entry.productionAlgorithmId)) throw new InvalidOperationException("Label custody is not a bijection.");
                mapping.Add(entry.anonymousLabel, entry.productionAlgorithmId);
            }
            string[] expectedAlgorithms = { NavigationAlgorithmIds.AStarRepeated, NavigationAlgorithmIds.DStarLite, NavigationAlgorithmIds.CorrectedFullRecomputeFlowField, NavigationAlgorithmIds.IncrementalDynamicFlowField };
            for (int index = 0; index < expectedAlgorithms.Length; index++) if (!algorithms.Contains(expectedAlgorithms[index])) throw new InvalidOperationException("Label custody production set is invalid.");
            string[] result = new string[4];
            for (int index = 0; index < result.Length; index++) if (!mapping.TryGetValue(requestedOrder[index], out result[index])) throw new InvalidOperationException("Frozen anonymous order contains a label absent from custody.");
            return result;
        }

        private static Gate14ReTB2FormalSuperblockV2 FindSuperblock(Gate14ReTB2FormalPlanV2 plan, string id)
        {
            Gate14ReTB2FormalSuperblockV2 found = null;
            for (int index = 0; index < plan.superblocks.Length; index++) if (plan.superblocks[index].superblockId == id) { if (found != null) throw new InvalidOperationException("Duplicate superblock id."); found = plan.superblocks[index]; }
            if (found == null) throw new InvalidOperationException("Requested superblock is absent from the frozen v2 plan.");
            return found;
        }

        private static void ValidateSuperblock(Gate14ReTB2FormalSuperblockV2 block)
        {
            if (block.hardTimeoutSeconds != 3600 || block.maximumWholeSuperblockTechnicalReplacements != 1 || block.anonymousLabelsInOrder == null || block.laneIdsInOrder == null || block.anonymousLabelsInOrder.Length != 4 || block.laneIdsInOrder.Length != 4)
                throw new InvalidOperationException("V2 superblock execution policy is invalid.");
            if (block.operationalChunkSequence != block.drawIndex || block.orderPermutationIndex < 1 || block.orderPermutationIndex > 6)
                throw new InvalidOperationException("V2 superblock operational chunk binding mismatch.");
            HashSet<string> labels = new HashSet<string>(block.anonymousLabelsInOrder, StringComparer.Ordinal);
            if (labels.Count != 4 || !labels.Contains("K1") || !labels.Contains("K2") || !labels.Contains("K3") || !labels.Contains("K4")) throw new InvalidOperationException("V2 anonymous label order is not a permutation.");
            for (int index = 0; index < 4; index++) if (block.laneIdsInOrder[index] != block.superblockId + "-" + block.anonymousLabelsInOrder[index] + "-O" + (index + 1).ToString(CultureInfo.InvariantCulture)) throw new InvalidOperationException("V2 lane id/order binding mismatch.");
            bool expectedTrace = (block.drawIndex >= 1 && block.drawIndex <= 6) || (block.drawIndex >= 163 && block.drawIndex <= 168) || (block.drawIndex >= 331 && block.drawIndex <= 336);
            if (block.traceCaptureRequired != expectedTrace) throw new InvalidOperationException("V2 trace subset binding mismatch.");
        }

        private static void ValidateBundleBinding(Gate14ReTB2InputBundleV1 value, Gate14ReTB2FormalSuperblockV2 block)
        {
            if (value == null || value.superblockId != block.superblockId || value.bundleSha256 != block.bundleSha256 || value.module != block.module || value.conditionId != block.conditionId || value.unitCount != block.unitCount || value.drawIndex != block.drawIndex || value.distanceStratum != block.distanceStratum)
                throw new InvalidOperationException("Adopted input bundle/v2 superblock binding mismatch.");
        }

        private void InstantiateUnitVisuals(ResolvedDeterministicScenario scenario)
        {
            if (unitVisualPrefab == null) throw new InvalidOperationException("Canonical unit visual prefab is not bound.");
            unitRoot = new GameObject("Gate14Re-TB2 anonymous rendered units lane " + (laneIndex + 1).ToString(CultureInfo.InvariantCulture));
            unitRoot.SetActive(false);
            ResearchGridWorldTransform transform = scenario.CreateWorldTransform();
            for (int index = 0; index < scenario.Agents.Count; index++)
            {
                ResolvedScenarioAgent agent = scenario.Agents[index];
                GameObject instance = Instantiate(unitVisualPrefab, unitRoot.transform);
                instance.name = "gate14re-tb2-unit-" + agent.AgentId.ToString("D4", CultureInfo.InvariantCulture);
                DisableLegacyMotion(instance);
                instance.transform.position = WithVisualHeight(transform.GridToWorldCenter(agent.Start, scenario.GridWidth, scenario.GridHeight));
                unitObjects.Add(instance);
            }
            unitRoot.SetActive(true);
            if (unitObjects.Count != scenario.Agents.Count || CountUnitsWithEnabledRenderer() != scenario.Agents.Count) throw new InvalidOperationException("Failed to instantiate and render the full population.");
        }

        private void UpdateUnitVisualPositions()
        {
            if (states.Count != unitObjects.Count) throw new InvalidOperationException("Unit state/render object count mismatch.");
            for (int index = 0; index < states.Count; index++) unitObjects[index].transform.position = WithVisualHeight(states[index].Position);
        }

        private int CountUnitsWithEnabledRenderer()
        {
            int count = 0;
            for (int index = 0; index < unitObjects.Count; index++)
            {
                Renderer[] renderers = unitObjects[index].GetComponentsInChildren<Renderer>(true);
                bool any = false;
                for (int renderer = 0; renderer < renderers.Length; renderer++) any |= renderers[renderer].enabled && renderers[renderer].gameObject.activeInHierarchy;
                if (any) count++;
            }
            return count;
        }

        private static INavigationPlanner CreatePlanner(string id)
        {
            if (id == NavigationAlgorithmIds.AStarRepeated) return new AStarRepeatedPlanner();
            if (id == NavigationAlgorithmIds.DStarLite) return new DStarLitePlanner();
            if (id == NavigationAlgorithmIds.CorrectedFullRecomputeFlowField) return new CorrectedFullRecomputeFlowFieldPlanner();
            if (id == NavigationAlgorithmIds.IncrementalDynamicFlowField) return new IncrementalDynamicFlowFieldPlanner();
            throw new InvalidOperationException("Custody resolved an unsupported production planner.");
        }

        private static GameObject CreateGridSurface(ResolvedDeterministicScenario scenario)
        {
            GameObject surface = GameObject.CreatePrimitive(PrimitiveType.Quad);
            surface.name = "Gate14Re-TB2 rendered navigation grid";
            Collider collider = surface.GetComponent<Collider>();
            if (collider != null) Destroy(collider);
            float width = scenario.GridWidth * scenario.CellSize;
            float height = scenario.GridHeight * scenario.CellSize;
            surface.transform.position = new Vector3(scenario.WorldOrigin.x + width * 0.5f, scenario.WorldOrigin.y - 0.05f, scenario.WorldOrigin.z + height * 0.5f);
            surface.transform.rotation = Quaternion.Euler(90f, 0f, 0f);
            surface.transform.localScale = new Vector3(width, height, 1f);
            return surface;
        }

        private static void ConfigureCamera(ResolvedDeterministicScenario scenario)
        {
            GameObject cameraObject = new GameObject("Gate14Re-TB2 frozen top-down camera v2");
            Camera camera = cameraObject.AddComponent<Camera>();
            float width = scenario.GridWidth * scenario.CellSize;
            float height = scenario.GridHeight * scenario.CellSize;
            cameraObject.transform.position = new Vector3(scenario.WorldOrigin.x + width * 0.5f, scenario.WorldOrigin.y + Math.Max(width, height) * 1.2f + 20f, scenario.WorldOrigin.z + height * 0.5f);
            cameraObject.transform.rotation = Quaternion.Euler(90f, 0f, 0f);
            camera.orthographic = true;
            camera.orthographicSize = Math.Max(height * 0.525f, width * 0.525f / (16f / 9f));
            camera.clearFlags = CameraClearFlags.SolidColor;
            camera.backgroundColor = new Color(0.015f, 0.018f, 0.022f, 1f);
            camera.nearClipPlane = 0.1f;
            camera.farClipPlane = Math.Max(width, height) * 3f + 100f;
        }

        private static void DisableLegacyMotion(GameObject instance)
        {
            MonoBehaviour[] scripts = instance.GetComponentsInChildren<MonoBehaviour>(true);
            for (int index = 0; index < scripts.Length; index++) scripts[index].enabled = false;
            NavMeshAgent[] agents = instance.GetComponentsInChildren<NavMeshAgent>(true);
            for (int index = 0; index < agents.Length; index++) agents[index].enabled = false;
            Collider[] colliders = instance.GetComponentsInChildren<Collider>(true);
            for (int index = 0; index < colliders.Length; index++) colliders[index].enabled = false;
            Rigidbody[] bodies = instance.GetComponentsInChildren<Rigidbody>(true);
            for (int index = 0; index < bodies.Length; index++) { bodies[index].velocity = Vector3.zero; bodies[index].angularVelocity = Vector3.zero; bodies[index].isKinematic = true; bodies[index].useGravity = false; }
        }

        private static void ConfigureEnvironment()
        {
            Application.runInBackground = true;
            Application.targetFrameRate = -1;
            QualitySettings.vSyncCount = 0;
            if (QualitySettings.names.Length > 5) QualitySettings.SetQualityLevel(5, true);
            Time.fixedDeltaTime = (float)Gate14ReTB2ProtocolV1.FixedStepSeconds;
            Screen.SetResolution(1920, 1080, FullScreenMode.FullScreenWindow);
        }

        private static Gate14ReTB2StructuralEventRawV1[] CopyEvents(IReadOnlyList<Gate14ReStructuralEventRecordV1> source)
        {
            Gate14ReTB2StructuralEventRawV1[] result = new Gate14ReTB2StructuralEventRawV1[source.Count];
            for (int index = 0; index < source.Count; index++)
            {
                Gate14ReStructuralEventRecordV1 item = source[index];
                result[index] = new Gate14ReTB2StructuralEventRawV1 { eventId = item.eventId, scheduledTick = item.scheduledTick, order = item.order, changedCellCount = item.changedCellCount, previousGridVersion = item.previousGridVersion, newGridVersion = item.newGridVersion, plannerRepairStatus = item.plannerRepairStatus, plannerFailureReason = item.plannerFailureReason, visualRevision = item.visualRevision };
            }
            return result;
        }

        private static void SummarizeFrameIntervals(double[] values, out double median, out double p95)
        {
            if (values == null || values.Length < 1) throw new InvalidOperationException("No rendered frame intervals were captured.");
            double[] ordered = (double[])values.Clone();
            Array.Sort(ordered);
            int middle = ordered.Length / 2;
            median = (ordered.Length & 1) == 1 ? ordered[middle] : 0.5d * (ordered[middle - 1] + ordered[middle]);
            int rank = Math.Max(1, (int)Math.Ceiling(0.95d * ordered.Length));
            p95 = ordered[rank - 1];
        }

        private void FinishFailure(Exception exception)
        {
            if (finishing) return;
            finishing = true;
            try
            {
                Gate14ReTB2FailureV2 failure = new Gate14ReTB2FailureV2
                {
                    schema = "gate14re-tb2-runner-failure-v2",
                    studyId = "Gate14Re-TB2",
                    status = "FAIL_CLOSED",
                    superblockId = superblock == null ? string.Empty : superblock.superblockId,
                    completedLaneCount = mode == "formal" ? completedLanes.Count : validatedLaneCount,
                    exceptionType = exception == null ? "unknown" : exception.GetType().FullName,
                    message = exception == null ? "Unknown runner failure." : exception.Message,
                    partialLaneOutputAdmissible = false,
                    formalObservationProduced = false,
                    collectionStarted = collectionStarted
                };
                string target = string.IsNullOrWhiteSpace(outputPath) ? string.Empty : (mode == "formal" ? outputPath + ".failure.json" : outputPath);
                if (!string.IsNullOrWhiteSpace(target) && !File.Exists(target)) WriteAtomicJson(target, failure, true);
            }
            catch { }
            productionPlannerIdsInOrder = null;
            UnityEngine.Debug.LogException(exception);
            FinishAndQuit(1);
        }

        private void FinishAndQuit(int exitCode) { phase = RuntimePhase.Finished; finishing = true; Application.Quit(exitCode); }

        private static string GetCurrentExecutablePath()
        {
            using (Process process = Process.GetCurrentProcess())
            {
                if (process.MainModule == null || string.IsNullOrWhiteSpace(process.MainModule.FileName)) throw new InvalidOperationException("Cannot resolve current executable path.");
                return Path.GetFullPath(process.MainModule.FileName);
            }
        }

        private static string GetCurrentAssemblyPath()
        {
            string location = typeof(Gate14ReTB2FormalControllerV2).Assembly.Location;
            if (string.IsNullOrWhiteSpace(location) || !File.Exists(location)) throw new InvalidOperationException("Cannot resolve Assembly-CSharp.dll.");
            return Path.GetFullPath(location);
        }

        private static string GetAdjacentBuildReceiptPath()
        {
            string path = Path.Combine(Path.GetDirectoryName(GetCurrentExecutablePath()), "build-receipt.v2.json");
            if (!File.Exists(path) || (File.GetAttributes(path) & FileAttributes.ReadOnly) == 0) throw new InvalidOperationException("Frozen v2 build receipt is missing or not ReadOnly.");
            return path;
        }

        private static int ParseAttempt(string value)
        {
            int parsed;
            if (!int.TryParse(value, NumberStyles.None, CultureInfo.InvariantCulture, out parsed) || (parsed != 1 && parsed != 2)) throw new InvalidOperationException("Whole-superblock attempt must be 1 or 2.");
            return parsed;
        }

        private static Dictionary<string, string> ParseArguments(string[] args)
        {
            Dictionary<string, string> result = new Dictionary<string, string>(StringComparer.Ordinal);
            for (int index = 0; index < args.Length; index++)
            {
                if (!args[index].StartsWith("--", StringComparison.Ordinal)) continue;
                string key = args[index].Substring(2);
                if (index + 1 >= args.Length || args[index + 1].StartsWith("--", StringComparison.Ordinal)) throw new InvalidOperationException("Missing value for --" + key + ".");
                result.Add(key, args[++index]);
            }
            return result;
        }

        private static string Required(Dictionary<string, string> arguments, string key)
        {
            string value;
            if (!arguments.TryGetValue(key, out value) || string.IsNullOrWhiteSpace(value)) throw new InvalidOperationException("Missing required --" + key + " argument.");
            return value;
        }

        private static string RequiredLowerSha(Dictionary<string, string> arguments, string key)
        {
            string value = Required(arguments, key).ToLowerInvariant();
            if (value.Length != 64) throw new InvalidOperationException("Invalid SHA-256 argument.");
            for (int index = 0; index < value.Length; index++) if (!Uri.IsHexDigit(value[index])) throw new InvalidOperationException("Invalid SHA-256 argument.");
            return value;
        }

        private static void RequireReadOnlyFile(string path, string sha256)
        {
            if (!File.Exists(path)) throw new FileNotFoundException("Required frozen file is missing.", path);
            if ((File.GetAttributes(path) & FileAttributes.ReadOnly) == 0) throw new InvalidOperationException("Required frozen file is not ReadOnly: " + path);
            if (Sha256File(path) != sha256) throw new InvalidOperationException("Required frozen file SHA-256 mismatch: " + path);
        }

        private static void RequireContained(string child, string parent, string label)
        {
            string normalizedParent = Path.GetFullPath(parent).TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar) + Path.DirectorySeparatorChar;
            string normalizedChild = Path.GetFullPath(child);
            if (string.Equals(normalizedChild.TrimEnd(Path.DirectorySeparatorChar), normalizedParent.TrimEnd(Path.DirectorySeparatorChar), StringComparison.OrdinalIgnoreCase)) return;
            if (!normalizedChild.StartsWith(normalizedParent, StringComparison.OrdinalIgnoreCase)) throw new InvalidOperationException(label + " escapes its authorized root.");
        }

        private static string Sha256File(string path)
        {
            using (FileStream stream = File.OpenRead(path))
            using (SHA256 sha = SHA256.Create()) return Hex(sha.ComputeHash(stream));
        }

        private static string Sha256Bytes(byte[] value)
        {
            using (SHA256 sha = SHA256.Create()) return Hex(sha.ComputeHash(value));
        }

        private static string Hex(byte[] digest)
        {
            StringBuilder builder = new StringBuilder(digest.Length * 2);
            for (int index = 0; index < digest.Length; index++) builder.Append(digest[index].ToString("x2", CultureInfo.InvariantCulture));
            return builder.ToString();
        }

        private static void WriteAtomicJson(string path, object value, bool allowDirectoryCreation)
        {
            string directory = Path.GetDirectoryName(path);
            if (allowDirectoryCreation) Directory.CreateDirectory(directory);
            if (!Directory.Exists(directory)) throw new DirectoryNotFoundException("Output directory does not exist: " + directory);
            if (File.Exists(path) || File.Exists(path + ".tmp")) throw new IOException("Output overwrite is forbidden: " + path);
            string temporary = path + ".tmp";
            string json = JsonUtility.ToJson(value, true).Replace("\r\n", "\n").Replace("\r", "\n") + "\n";
            File.WriteAllText(temporary, json, new UTF8Encoding(false));
            File.Move(temporary, path);
        }

        private static bool IsFinite(Vector3 position) { return !(float.IsNaN(position.x) || float.IsNaN(position.y) || float.IsNaN(position.z) || float.IsInfinity(position.x) || float.IsInfinity(position.y) || float.IsInfinity(position.z)); }
        private static Vector3 WithVisualHeight(Vector3 position) { position.y += 1f; return position; }
        private static string Forward(string path) { return path.Replace('\\', '/'); }
    }
}

using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Security.Cryptography;
using System.Text;
using DDM.Research.Algorithms;
using DDM.Research.Gate14Re.V1;
using DDM.Research.Grid;
using DDM.Research.Navigation;
using DDM.Research.Scenarios;
using UnityEngine;
using UnityEngine.AI;

namespace DDM.Research.Gate14Re.V2
{
    public sealed class Gate14ReFormalControllerV1 : MonoBehaviour
    {
        private enum RuntimePhase
        {
            None,
            ValidationMovement,
            Movement,
            M4Warmup,
            M4Measure,
            BetweenAlgorithms,
            Finished
        }

        public GameObject unitVisualPrefab;

        private readonly List<GameObject> unitObjects = new List<GameObject>();
        private readonly List<Gate14ReMovementAlgorithmRawV1> movementResults = new List<Gate14ReMovementAlgorithmRawV1>();
        private readonly List<Gate14ReM4AlgorithmRawV1> m4Results = new List<Gate14ReM4AlgorithmRawV1>();
        private readonly List<double> frameIntervals = new List<double>(1800);

        private RuntimePhase phase;
        private string mode;
        private string outputPath;
        private string planSha256;
        private string executableSha256;
        private string assemblyCSharpSha256;
        private string buildReceiptSha256;
        private string authorizationId;
        private bool formalPhaseAStarted;
        private Gate14ReFormalBlockV1 block;
        private Gate14RePreparedScenario prepared;
        private Gate14ReMovementKernelV1 kernel;
        private Gate14ReTextureVisualGridV1 textureVisual;
        private GameObject unitRoot;
        private GameObject gridSurface;
        private int algorithmIndex;
        private long[] arrivalTicks;
        private int validationAlgorithmsInitialized;
        private int betweenFrames;
        private int warmupFrames;
        private long previousFrameTimestamp;
        private bool finishing;

        private void Start()
        {
            try
            {
                Dictionary<string, string> arguments = ParseArguments(Environment.GetCommandLineArgs());
                mode = Required(arguments, "gate14re-mode");
                if (mode != "validation" && mode != "formal") throw new InvalidOperationException("Runner mode must be validation or formal.");

                string projectRoot = Path.GetFullPath(Required(arguments, "gate14re-project-root"));
                string planPath = Path.GetFullPath(Required(arguments, "gate14re-plan"));
                planSha256 = RequiredLowerSha(arguments, "gate14re-plan-sha256");
                outputPath = Path.GetFullPath(Required(arguments, "gate14re-output"));
                string blockId = Required(arguments, "gate14re-block-id");

                RequireReadOnlyFile(planPath, planSha256);
                Gate14ReFormalPlanV1 plan = JsonUtility.FromJson<Gate14ReFormalPlanV1>(File.ReadAllText(planPath, Encoding.UTF8));
                ValidatePlanHeader(plan);
                block = FindAndValidateBlock(plan, blockId);
                executableSha256 = Sha256File(GetCurrentExecutablePath());
                assemblyCSharpSha256 = Sha256File(GetCurrentAssemblyPath());
                buildReceiptSha256 = Sha256File(GetAdjacentBuildReceiptPath());

                if (mode == "formal")
                {
                    ValidateFormalAuthorization(arguments, planPath, projectRoot);
                    formalPhaseAStarted = true;
                }
                else
                {
                    string verificationRoot = Path.GetFullPath(Path.Combine(projectRoot, "Research", "Verification", "Gate14Re"));
                    RequireContained(outputPath, verificationRoot, "Validation output");
                    Directory.CreateDirectory(Path.GetDirectoryName(outputPath));
                }

                ConfigureEnvironment();
                string scenarioPath = Path.GetFullPath(Path.Combine(projectRoot, block.scenarioRelativePath.Replace('/', Path.DirectorySeparatorChar)));
                FileInfo scenarioInfo = new FileInfo(scenarioPath);
                if (!scenarioInfo.Exists || scenarioInfo.Length != block.scenarioBytes || Sha256File(scenarioPath) != block.scenarioSha256)
                    throw new InvalidOperationException("Block scenario binding failed.");
                LoadedDeterministicScenario loaded = DeterministicScenarioJson.LoadFromFile(scenarioPath);
                prepared = Gate14ReProtocolV1.Prepare(loaded, block.scenarioId, block.scenarioSha256, block.conditionId, block.dynamicFootprintCells, block.unitCount);
                ConfigureCamera(prepared.Resolved);
                algorithmIndex = 0;
                InitializeCurrentAlgorithm();
            }
            catch (Exception exception)
            {
                FinishFailure(exception);
            }
        }

        private void Update()
        {
            if (finishing || kernel == null) return;
            try
            {
                if (phase == RuntimePhase.ValidationMovement)
                {
                    RunValidationSlice();
                }
                else if (phase == RuntimePhase.Movement)
                {
                    RunAcceleratedMovementSlice();
                }
                else if (phase == RuntimePhase.BetweenAlgorithms)
                {
                    betweenFrames++;
                    if (betweenFrames >= 1) InitializeCurrentAlgorithm();
                }
            }
            catch (Exception exception)
            {
                FinishFailure(exception);
            }
        }

        private void FixedUpdate()
        {
            if (finishing || kernel == null || (phase != RuntimePhase.M4Warmup && phase != RuntimePhase.M4Measure)) return;
            try
            {
                if (!AllUnitsTerminal(kernel) && kernel.CurrentTick + 1L < Gate14ReProtocolV1.MovementCapTicks)
                {
                    kernel.AdvanceOneFixedTick();
                    UpdateUnitVisualPositions();
                }
            }
            catch (Exception exception)
            {
                FinishFailure(exception);
            }
        }

        private void LateUpdate()
        {
            if (finishing || kernel == null) return;
            try
            {
                if (phase == RuntimePhase.M4Warmup)
                {
                    warmupFrames++;
                    if (warmupFrames >= 600)
                    {
                        previousFrameTimestamp = Stopwatch.GetTimestamp();
                        phase = RuntimePhase.M4Measure;
                    }
                }
                else if (phase == RuntimePhase.M4Measure)
                {
                    long now = Stopwatch.GetTimestamp();
                    double interval = (double)(now - previousFrameTimestamp) / Stopwatch.Frequency;
                    previousFrameTimestamp = now;
                    if (interval <= 0d || double.IsNaN(interval) || double.IsInfinity(interval))
                        throw new InvalidOperationException("Non-positive or non-finite rendered frame interval.");
                    frameIntervals.Add(interval);
                    if (frameIntervals.Count == 1800) CompleteM4Algorithm();
                }
            }
            catch (Exception exception)
            {
                FinishFailure(exception);
            }
        }

        private void InitializeCurrentAlgorithm()
        {
            ClearAlgorithmWorld();
            betweenFrames = 0;
            if (algorithmIndex < 0 || algorithmIndex >= 4) throw new InvalidOperationException("Algorithm order position is outside 0..3.");
            if (block.algorithmIdsInOrder == null || block.algorithmIdsInOrder.Length != 4 || block.algorithmLabelsInOrder == null || block.algorithmLabelsInOrder.Length != 4)
                throw new InvalidOperationException("Block algorithm order is incomplete.");

            gridSurface = CreateGridSurface(prepared.Resolved);
            textureVisual = new Gate14ReTextureVisualGridV1(gridSurface.GetComponent<Renderer>());
            InstantiateUnitVisuals(prepared.Resolved);
            kernel = new Gate14ReMovementKernelV1(
                block.blockId + "-order-" + (algorithmIndex + 1).ToString(CultureInfo.InvariantCulture),
                prepared.Resolved,
                CreatePlanner(block.algorithmIdsInOrder[algorithmIndex]),
                textureVisual);
            kernel.Release();
            arrivalTicks = new long[prepared.Resolved.Agents.Count];
            for (int index = 0; index < arrivalTicks.Length; index++) arrivalTicks[index] = -1L;
            UpdateUnitVisualPositions();

            if (mode == "validation")
            {
                phase = RuntimePhase.ValidationMovement;
            }
            else if (block.lane == "movement")
            {
                phase = RuntimePhase.Movement;
            }
            else if (block.lane == "m4")
            {
                warmupFrames = 0;
                frameIntervals.Clear();
                previousFrameTimestamp = 0L;
                phase = RuntimePhase.M4Warmup;
            }
            else
            {
                throw new InvalidOperationException("Unsupported block lane: " + block.lane);
            }
        }

        private void RunValidationSlice()
        {
            int guard = 0;
            while (kernel.CurrentTick < 10L && guard++ < 32) kernel.AdvanceOneFixedTick();
            UpdateUnitVisualPositions();
            if (kernel.CurrentTick < 10L || kernel.StructuralEventRecords.Count != 2 || kernel.GridVersion != kernel.PlannerGridVersion || textureVisual.VisualRevision != kernel.GridVersion)
                throw new InvalidOperationException("Formal runner validation did not apply the first ordered event pair in grid/planner/visual lockstep.");

            validationAlgorithmsInitialized++;
            algorithmIndex++;
            if (algorithmIndex < 4)
            {
                phase = RuntimePhase.BetweenAlgorithms;
                betweenFrames = 0;
                return;
            }

            Gate14ReValidationMarkerV1 marker = new Gate14ReValidationMarkerV1
            {
                schema = "gate14re-formal-runner-validation-marker-v1",
                studyId = "Gate14Re",
                status = "PASS",
                lane = block.lane,
                unitCount = block.unitCount,
                algorithmsStructurallyInitialized = validationAlgorithmsInitialized,
                structuralEventCount = 2,
                gridPlannerVisualRevisionMatch = true,
                formalObservationProduced = false,
                m1ThroughM5OutputProduced = false,
                formalPhaseAStarted = false
            };
            WriteAtomicJson(outputPath, marker, true);
            FinishAndQuit(0);
        }

        private void RunAcceleratedMovementSlice()
        {
            int ticks = 0;
            while (ticks++ < 256 && !AllUnitsTerminal(kernel) && kernel.CurrentTick + 1L < Gate14ReProtocolV1.MovementCapTicks)
            {
                kernel.AdvanceOneFixedTick();
                CaptureArrivalTicks();
            }
            UpdateUnitVisualPositions();
            if (AllUnitsTerminal(kernel) || kernel.CurrentTick + 1L >= Gate14ReProtocolV1.MovementCapTicks) CompleteMovementAlgorithm();
        }

        private void CompleteMovementAlgorithm()
        {
            CaptureArrivalTicks();
            IReadOnlyList<Gate14ReUnitStateV1> states = kernel.Units;
            Gate14ReUnitRawV1[] units = new Gate14ReUnitRawV1[states.Count];
            int arrived = 0;
            int active = 0;
            int noPath = 0;
            int budget = 0;
            int invalid = 0;
            int internalFailure = 0;
            List<string> critical = new List<string>();
            HashSet<int> identities = new HashSet<int>();

            for (int index = 0; index < states.Count; index++)
            {
                Gate14ReUnitStateV1 state = states[index];
                if (!identities.Add(state.AgentId)) critical.Add("duplicate_agent_identity:" + state.AgentId.ToString(CultureInfo.InvariantCulture));
                switch (state.State)
                {
                    case Gate14ReUnitTerminalStateV1.Arrived: arrived++; break;
                    case Gate14ReUnitTerminalStateV1.Active: active++; break;
                    case Gate14ReUnitTerminalStateV1.NoPath: noPath++; break;
                    case Gate14ReUnitTerminalStateV1.BudgetExceeded: budget++; break;
                    case Gate14ReUnitTerminalStateV1.InvalidPlan:
                        invalid++;
                        critical.Add("illegal_or_invalid_plan:" + state.AgentId.ToString(CultureInfo.InvariantCulture));
                        break;
                    case Gate14ReUnitTerminalStateV1.InternalFailure: internalFailure++; break;
                }
                if (!IsFinite(state.Position)) critical.Add("nonfinite_position:" + state.AgentId.ToString(CultureInfo.InvariantCulture));
                if (state.State == Gate14ReUnitTerminalStateV1.Arrived && (!state.CurrentCell.Equals(state.Goal) || arrivalTicks[index] < 0L))
                    critical.Add("wrong_goal_completion:" + state.AgentId.ToString(CultureInfo.InvariantCulture));
                units[index] = new Gate14ReUnitRawV1
                {
                    agentId = state.AgentId,
                    terminalState = state.State.ToString(),
                    arrived = state.State == Gate14ReUnitTerminalStateV1.Arrived,
                    arrivalTick = arrivalTicks[index],
                    cumulativeHorizontalPathLength = state.CumulativeHorizontalPathLength
                };
            }
            if (identities.Count != block.unitCount) critical.Add("missing_agent_identity");

            movementResults.Add(new Gate14ReMovementAlgorithmRawV1
            {
                algorithmLabel = block.algorithmLabelsInOrder[algorithmIndex],
                productionAlgorithmId = block.algorithmIdsInOrder[algorithmIndex],
                orderPosition = algorithmIndex + 1,
                unitCount = states.Count,
                allUnitsArrived = arrived == states.Count,
                arrivedCount = arrived,
                activeAtCapCount = active,
                noPathCount = noPath,
                budgetExceededCount = budget,
                invalidPlanCount = invalid,
                internalFailureCount = internalFailure,
                m1Seconds = arrived == states.Count ? Math.Max(0d, (kernel.CurrentTick + 1L) * Gate14ReProtocolV1.FixedStepSeconds) : 180d,
                m5CriticalViolationCount = critical.Count,
                m5CriticalViolationCodes = critical.ToArray(),
                structuralEventCount = kernel.StructuralEventRecords.Count,
                units = units,
                structuralEvents = CopyEvents(kernel.StructuralEventRecords),
                m2CommonMaskCount = 0,
                m2CommonMaskSufficient = false,
                m2CommonMaskMeanPathLength = -1d
            });
            AdvanceAlgorithmOrFinish();
        }

        private void CompleteM4Algorithm()
        {
            if (frameIntervals.Count != 1800) throw new InvalidOperationException("M4 did not capture exactly 1,800 frame intervals.");
            double[] raw = frameIntervals.ToArray();
            double median;
            double p95;
            Gate14ReFormalMathV1.SummarizeFrameIntervals(raw, out median, out p95);
            int enabled = CountUnitsWithEnabledRenderer();
            if (enabled != block.unitCount) throw new InvalidOperationException("M4 full-population renderer count changed during measurement.");

            m4Results.Add(new Gate14ReM4AlgorithmRawV1
            {
                algorithmLabel = block.algorithmLabelsInOrder[algorithmIndex],
                productionAlgorithmId = block.algorithmIdsInOrder[algorithmIndex],
                orderPosition = algorithmIndex + 1,
                unitCount = block.unitCount,
                unitsWithEnabledRenderer = enabled,
                warmupRenderedFrames = 600,
                measuredRenderedFrameIntervals = raw.Length,
                frameIntervalsSeconds = raw,
                medianFrameTimeSeconds = median,
                nearestRankP95FrameTimeSeconds = p95,
                simulationTickAtEnd = kernel.CurrentTick,
                structuralEventCount = kernel.StructuralEventRecords.Count,
                structuralEvents = CopyEvents(kernel.StructuralEventRecords)
            });
            AdvanceAlgorithmOrFinish();
        }

        private void AdvanceAlgorithmOrFinish()
        {
            algorithmIndex++;
            if (algorithmIndex < 4)
            {
                phase = RuntimePhase.BetweenAlgorithms;
                betweenFrames = 0;
                return;
            }
            WriteFormalBlockOutput();
            FinishAndQuit(0);
        }

        private void WriteFormalBlockOutput()
        {
            if (mode != "formal") throw new InvalidOperationException("Formal block output is forbidden outside formal mode.");
            int minimum = Math.Max(1, (int)Math.Ceiling(0.8d * block.unitCount));
            int[] commonMask = new int[0];
            bool maskSufficient = false;
            if (block.lane == "movement")
            {
                commonMask = Gate14ReFormalMathV1.ComputeAndApplyCommonM2Mask(movementResults.ToArray(), minimum);
                maskSufficient = commonMask.Length >= minimum;
            }

            Gate14ReFormalBlockOutputV1 output = new Gate14ReFormalBlockOutputV1
            {
                schema = "gate14re-formal-block-output-v2",
                studyId = "Gate14Re",
                status = "COMPLETE",
                blockId = block.blockId,
                blockSequence = block.sequence,
                module = block.module,
                lane = block.lane,
                conditionId = block.conditionId,
                scenarioId = block.scenarioId,
                scenarioSha256 = block.scenarioSha256,
                unitCount = block.unitCount,
                blockIndex = block.blockIndex,
                williamsRow = block.williamsRow,
                planSha256 = planSha256,
                executableSha256 = executableSha256,
                assemblyCSharpSha256 = assemblyCSharpSha256,
                buildReceiptSha256 = buildReceiptSha256,
                authorizationId = authorizationId,
                m2CommonMaskMinimum = block.lane == "movement" ? minimum : 0,
                m2CommonMaskAgentIds = commonMask,
                m2CommonMaskSufficient = block.lane == "movement" && maskSufficient,
                movement = movementResults.ToArray(),
                m4 = m4Results.ToArray(),
                completeFourAlgorithmBlock = movementResults.Count == 4 || m4Results.Count == 4,
                formalObservationProduced = true,
                formalPhaseA = true
            };
            if (!output.completeFourAlgorithmBlock) throw new InvalidOperationException("A formal output requires all four algorithm samples in one complete block.");
            WriteAtomicJson(outputPath, output, false);
        }

        private void CaptureArrivalTicks()
        {
            IReadOnlyList<Gate14ReUnitStateV1> states = kernel.Units;
            for (int index = 0; index < states.Count; index++)
            {
                if (arrivalTicks[index] < 0L && states[index].State == Gate14ReUnitTerminalStateV1.Arrived) arrivalTicks[index] = kernel.CurrentTick;
            }
        }

        private void InstantiateUnitVisuals(ResolvedDeterministicScenario scenario)
        {
            if (unitVisualPrefab == null) throw new InvalidOperationException("Canonical unit visual prefab is not bound.");
            unitRoot = new GameObject("Gate14Re formal units");
            unitRoot.SetActive(false);
            ResearchGridWorldTransform transform = scenario.CreateWorldTransform();
            for (int index = 0; index < scenario.Agents.Count; index++)
            {
                ResolvedScenarioAgent agent = scenario.Agents[index];
                GameObject instance = Instantiate(unitVisualPrefab, unitRoot.transform);
                instance.name = "gate14re-formal-unit-" + agent.AgentId.ToString("D4", CultureInfo.InvariantCulture);
                DisableLegacyMotion(instance);
                instance.transform.position = WithVisualHeight(transform.GridToWorldCenter(agent.Start, scenario.GridWidth, scenario.GridHeight));
                unitObjects.Add(instance);
            }
            unitRoot.SetActive(true);
            if (unitObjects.Count != scenario.Agents.Count || CountUnitsWithEnabledRenderer() != scenario.Agents.Count)
                throw new InvalidOperationException("Failed to instantiate and render the full Gate 14Re population.");
        }

        private void UpdateUnitVisualPositions()
        {
            IReadOnlyList<Gate14ReUnitStateV1> states = kernel.Units;
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

        private void ClearAlgorithmWorld()
        {
            kernel = null;
            arrivalTicks = null;
            unitObjects.Clear();
            if (textureVisual != null) textureVisual.Dispose();
            textureVisual = null;
            if (unitRoot != null) Destroy(unitRoot);
            if (gridSurface != null) Destroy(gridSurface);
            unitRoot = null;
            gridSurface = null;
        }

        private void ValidateFormalAuthorization(Dictionary<string, string> arguments, string planPath, string projectRoot)
        {
            string authorizationPath = Path.GetFullPath(Required(arguments, "gate14re-formal-authorization"));
            string authorizationSha = RequiredLowerSha(arguments, "gate14re-formal-authorization-sha256");
            RequireReadOnlyFile(authorizationPath, authorizationSha);
            Gate14ReFormalAuthorizationV1 authorization = JsonUtility.FromJson<Gate14ReFormalAuthorizationV1>(File.ReadAllText(authorizationPath, Encoding.UTF8));
            if (authorization == null || authorization.schema != "gate14re-formal-phase-a-authorization-v2" || authorization.studyId != "Gate14Re" || authorization.status != "AUTHORIZED")
                throw new InvalidOperationException("Formal authorization schema/status binding failed.");
            if (!authorization.userExplicitlyAuthorizedFormalPhaseA) throw new InvalidOperationException("Formal Phase A lacks explicit user authorization.");
            if (authorization.planSha256 != planSha256 || authorization.executableSha256 != executableSha256 || authorization.assemblyCSharpSha256 != assemblyCSharpSha256 || authorization.buildReceiptSha256 != buildReceiptSha256)
                throw new InvalidOperationException("Formal authorization does not bind this plan, executable, managed assembly, and build receipt.");
            if (string.IsNullOrWhiteSpace(authorization.authorizationId)) throw new InvalidOperationException("Formal authorization id is missing.");
            string formalRoot = Path.GetFullPath(authorization.formalRoot);
            string expectedParent = Path.GetFullPath(Path.Combine(projectRoot, "Research", "FormalRuns", "Gate14Re"));
            RequireContained(formalRoot, expectedParent, "Formal root");
            RequireContained(outputPath, formalRoot, "Formal block output");
            if (!Directory.Exists(formalRoot) || !Directory.Exists(Path.GetDirectoryName(outputPath)))
                throw new DirectoryNotFoundException("The authorized supervisor must create the formal root and block directory before launch.");
            if (File.Exists(outputPath) || File.Exists(outputPath + ".tmp")) throw new IOException("Formal block output already exists; overwrite/resume is forbidden.");
            authorizationId = authorization.authorizationId;
        }

        private static void ValidatePlanHeader(Gate14ReFormalPlanV1 plan)
        {
            if (plan == null || plan.schema != "gate14re-formal-block-plan-v1" || plan.studyId != "Gate14Re" || plan.version != 1 || plan.status != "FROZEN_NONEXECUTING")
                throw new InvalidOperationException("Formal plan header is invalid.");
            if (plan.fixedB != 48 || plan.plannedValidProcesses != 1536 || plan.blocks == null || plan.blocks.Length != 1536)
                throw new InvalidOperationException("Formal plan size/B binding is invalid.");
        }

        private static Gate14ReFormalBlockV1 FindAndValidateBlock(Gate14ReFormalPlanV1 plan, string blockId)
        {
            Gate14ReFormalBlockV1 found = null;
            for (int index = 0; index < plan.blocks.Length; index++)
            {
                if (plan.blocks[index].blockId == blockId)
                {
                    if (found != null) throw new InvalidOperationException("Duplicate formal block id.");
                    found = plan.blocks[index];
                }
            }
            if (found == null) throw new InvalidOperationException("Requested formal block is absent from the frozen plan.");
            if (found.sequence < 1 || found.sequence > 1536 || found.blockIndex < 1 || found.blockIndex > 48 || found.williamsRow < 1 || found.williamsRow > 4)
                throw new InvalidOperationException("Formal block indices are invalid.");
            if (found.maximumWholeBlockReplacements != 1) throw new InvalidOperationException("Formal block replacement policy drifted.");
            return found;
        }

        private static Gate14ReStructuralEventRawV1[] CopyEvents(IReadOnlyList<Gate14ReStructuralEventRecordV1> source)
        {
            Gate14ReStructuralEventRawV1[] result = new Gate14ReStructuralEventRawV1[source.Count];
            for (int index = 0; index < source.Count; index++)
            {
                Gate14ReStructuralEventRecordV1 item = source[index];
                result[index] = new Gate14ReStructuralEventRawV1
                {
                    eventId = item.eventId,
                    scheduledTick = item.scheduledTick,
                    order = item.order,
                    changedCellCount = item.changedCellCount,
                    previousGridVersion = item.previousGridVersion,
                    newGridVersion = item.newGridVersion,
                    plannerRepairStatus = item.plannerRepairStatus,
                    plannerFailureReason = item.plannerFailureReason,
                    visualRevision = item.visualRevision
                };
            }
            return result;
        }

        private static bool AllUnitsTerminal(Gate14ReMovementKernelV1 movement)
        {
            IReadOnlyList<Gate14ReUnitStateV1> states = movement.Units;
            for (int index = 0; index < states.Count; index++) if (states[index].State == Gate14ReUnitTerminalStateV1.Active) return false;
            return true;
        }

        private static INavigationPlanner CreatePlanner(string id)
        {
            if (id == NavigationAlgorithmIds.AStarRepeated) return new AStarRepeatedPlanner();
            if (id == NavigationAlgorithmIds.DStarLite) return new DStarLitePlanner();
            if (id == NavigationAlgorithmIds.CorrectedFullRecomputeFlowField) return new CorrectedFullRecomputeFlowFieldPlanner();
            if (id == NavigationAlgorithmIds.IncrementalDynamicFlowField) return new IncrementalDynamicFlowFieldPlanner();
            throw new ArgumentOutOfRangeException("id", "Unknown production planner id.");
        }

        private static GameObject CreateGridSurface(ResolvedDeterministicScenario scenario)
        {
            GameObject surface = GameObject.CreatePrimitive(PrimitiveType.Quad);
            surface.name = "Gate14Re formal rendered navigation grid";
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
            GameObject cameraObject = new GameObject("Gate14Re formal top-down camera");
            Camera camera = cameraObject.AddComponent<Camera>();
            float width = scenario.GridWidth * scenario.CellSize;
            float height = scenario.GridHeight * scenario.CellSize;
            float centerX = scenario.WorldOrigin.x + width * 0.5f;
            float centerZ = scenario.WorldOrigin.z + height * 0.5f;
            cameraObject.transform.position = new Vector3(centerX, scenario.WorldOrigin.y + Math.Max(width, height) * 1.2f + 20f, centerZ);
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
            for (int index = 0; index < bodies.Length; index++)
            {
                bodies[index].velocity = Vector3.zero;
                bodies[index].angularVelocity = Vector3.zero;
                bodies[index].isKinematic = true;
                bodies[index].useGravity = false;
            }
        }

        private static void ConfigureEnvironment()
        {
            Application.runInBackground = true;
            Application.targetFrameRate = -1;
            QualitySettings.vSyncCount = 0;
            if (QualitySettings.names.Length > 5) QualitySettings.SetQualityLevel(5, true);
            Time.fixedDeltaTime = (float)Gate14ReProtocolV1.FixedStepSeconds;
            Screen.SetResolution(1920, 1080, FullScreenMode.FullScreenWindow);
        }

        private void FinishFailure(Exception exception)
        {
            if (finishing) return;
            finishing = true;
            try
            {
                Gate14ReFormalFailureV1 failure = new Gate14ReFormalFailureV1
                {
                    schema = "gate14re-formal-runner-failure-v1",
                    studyId = "Gate14Re",
                    status = "FAIL_CLOSED",
                    blockId = block == null ? string.Empty : block.blockId,
                    exceptionType = exception == null ? "unknown" : exception.GetType().FullName,
                    message = exception == null ? "Unknown runner failure." : exception.Message,
                    formalObservationProduced = false,
                    partialBlockAdmissible = false,
                    formalPhaseAStarted = formalPhaseAStarted
                };
                string target = string.IsNullOrWhiteSpace(outputPath) ? string.Empty : (mode == "formal" ? outputPath + ".failure.json" : outputPath);
                if (!string.IsNullOrWhiteSpace(target) && !File.Exists(target)) WriteAtomicJson(target, failure, true);
            }
            catch { }
            UnityEngine.Debug.LogException(exception);
            FinishAndQuit(1);
        }

        private void FinishAndQuit(int exitCode)
        {
            phase = RuntimePhase.Finished;
            finishing = true;
            Application.Quit(exitCode);
        }

        private static string GetCurrentExecutablePath()
        {
            using (Process process = Process.GetCurrentProcess())
            {
                if (process.MainModule == null || string.IsNullOrWhiteSpace(process.MainModule.FileName)) throw new InvalidOperationException("Cannot resolve the current executable path.");
                return Path.GetFullPath(process.MainModule.FileName);
            }
        }

        private static string GetCurrentAssemblyPath()
        {
            string location = typeof(Gate14ReFormalControllerV1).Assembly.Location;
            if (string.IsNullOrWhiteSpace(location) || !File.Exists(location)) throw new InvalidOperationException("Cannot resolve Assembly-CSharp.dll for formal binding.");
            return Path.GetFullPath(location);
        }

        private static string GetAdjacentBuildReceiptPath()
        {
            string path = Path.Combine(Path.GetDirectoryName(GetCurrentExecutablePath()), "build-receipt.v2.json");
            if (!File.Exists(path)) throw new FileNotFoundException("Versioned formal build receipt is missing.", path);
            if ((File.GetAttributes(path) & FileAttributes.ReadOnly) == 0) throw new InvalidOperationException("Versioned formal build receipt is not ReadOnly.");
            return path;
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
            if (!normalizedChild.StartsWith(normalizedParent, StringComparison.OrdinalIgnoreCase)) throw new InvalidOperationException(label + " escapes its authorized root.");
        }

        private static Dictionary<string, string> ParseArguments(string[] args)
        {
            Dictionary<string, string> result = new Dictionary<string, string>(StringComparer.Ordinal);
            for (int index = 0; index < args.Length; index++)
            {
                string item = args[index];
                if (!item.StartsWith("--", StringComparison.Ordinal)) continue;
                string key = item.Substring(2);
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
            if (value.Length != 64) throw new InvalidOperationException("Invalid SHA-256 for --" + key + ".");
            for (int index = 0; index < value.Length; index++) if (!Uri.IsHexDigit(value[index])) throw new InvalidOperationException("Invalid SHA-256 for --" + key + ".");
            return value;
        }

        private static string Sha256File(string path)
        {
            using (FileStream stream = File.OpenRead(path))
            using (SHA256 sha = SHA256.Create())
            {
                byte[] digest = sha.ComputeHash(stream);
                StringBuilder builder = new StringBuilder(digest.Length * 2);
                for (int index = 0; index < digest.Length; index++) builder.Append(digest[index].ToString("x2", CultureInfo.InvariantCulture));
                return builder.ToString();
            }
        }

        private static void WriteAtomicJson(string path, object value, bool allowDirectoryCreation)
        {
            string directory = Path.GetDirectoryName(path);
            if (allowDirectoryCreation) Directory.CreateDirectory(directory);
            if (!Directory.Exists(directory)) throw new DirectoryNotFoundException("Output directory does not exist: " + directory);
            if (File.Exists(path)) throw new IOException("Output overwrite is forbidden: " + path);
            string temp = path + ".tmp";
            if (File.Exists(temp)) throw new IOException("Output temp path already exists: " + temp);
            string json = JsonUtility.ToJson(value, true).Replace("\r\n", "\n").Replace("\r", "\n") + "\n";
            File.WriteAllText(temp, json, new UTF8Encoding(false));
            File.Move(temp, path);
        }

        private static bool IsFinite(Vector3 position)
        {
            return !(float.IsNaN(position.x) || float.IsNaN(position.y) || float.IsNaN(position.z) || float.IsInfinity(position.x) || float.IsInfinity(position.y) || float.IsInfinity(position.z));
        }

        private static Vector3 WithVisualHeight(Vector3 position)
        {
            position.y += 1f;
            return position;
        }
    }
}

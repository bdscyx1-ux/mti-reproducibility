using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Security.Cryptography;
using System.Text;
using DDM.Research.Navigation;
using UnityEngine;

namespace DDM.Research.Scenarios
{
    public sealed class ScenarioJsonFormatException : FormatException
    {
        public int CharacterIndex { get; private set; }

        public ScenarioJsonFormatException(string message, int characterIndex)
            : base(string.Format(CultureInfo.InvariantCulture, "{0} (character {1}).", message, characterIndex))
        {
            CharacterIndex = characterIndex;
        }
    }

    public sealed class LoadedDeterministicScenario
    {
        public string SourcePath { get; private set; }
        public string SourceSha256 { get; private set; }
        public DeterministicScenarioDefinition Definition { get; private set; }
        public ResolvedDeterministicScenario Resolved { get; private set; }

        internal LoadedDeterministicScenario(
            string sourcePath,
            string sourceSha256,
            DeterministicScenarioDefinition definition,
            ResolvedDeterministicScenario resolved)
        {
            SourcePath = sourcePath ?? string.Empty;
            SourceSha256 = sourceSha256 ?? string.Empty;
            Definition = definition;
            Resolved = resolved;
        }
    }

    /// <summary>
    /// Strict schema-v1 JSON boundary for deterministic scenario files. Unknown,
    /// misplaced, duplicate, and missing fields are rejected before JsonUtility runs.
    /// </summary>
    public static class DeterministicScenarioJson
    {
        public const int MaximumUtf8Bytes = 16 * 1024 * 1024;
        private static readonly UTF8Encoding StrictUtf8 = new UTF8Encoding(false, true);

        public static LoadedDeterministicScenario LoadFromFile(string filePath)
        {
            if (string.IsNullOrWhiteSpace(filePath)) throw new ArgumentException("Scenario file path is required.", "filePath");
            string fullPath = Path.GetFullPath(filePath);
            FileInfo file = new FileInfo(fullPath);
            if (!file.Exists) throw new FileNotFoundException("Scenario JSON file was not found.", fullPath);
            if (file.Length > MaximumUtf8Bytes) throw new InvalidDataException("Scenario JSON exceeds the 16 MiB input limit.");

            byte[] bytes = File.ReadAllBytes(fullPath);
            string json = DecodeUtf8(bytes);
            return ParseInternal(json, fullPath, ComputeSha256(bytes));
        }

        public static LoadedDeterministicScenario Parse(string json)
        {
            if (json == null) throw new ArgumentNullException("json");
            byte[] bytes = StrictUtf8.GetBytes(json);
            if (bytes.Length > MaximumUtf8Bytes) throw new InvalidDataException("Scenario JSON exceeds the 16 MiB input limit.");
            return ParseInternal(RemoveLeadingBom(json), string.Empty, ComputeSha256(bytes));
        }

        public static string SerializeCanonical(ResolvedDeterministicScenario scenario)
        {
            if (scenario == null) throw new ArgumentNullException("scenario");
            DeterministicScenarioDefinition canonical = BuildCanonicalDefinition(scenario);
            string json = JsonUtility.ToJson(canonical, true).Replace("\r\n", "\n").Replace("\r", "\n");
            return json.EndsWith("\n", StringComparison.Ordinal) ? json : json + "\n";
        }

        public static string SaveCanonical(string filePath, ResolvedDeterministicScenario scenario, bool overwrite = false)
        {
            if (string.IsNullOrWhiteSpace(filePath)) throw new ArgumentException("Scenario file path is required.", "filePath");
            string fullPath = Path.GetFullPath(filePath);
            string directory = Path.GetDirectoryName(fullPath);
            if (!string.IsNullOrEmpty(directory)) Directory.CreateDirectory(directory);

            byte[] bytes = StrictUtf8.GetBytes(SerializeCanonical(scenario));
            FileMode mode = overwrite ? FileMode.Create : FileMode.CreateNew;
            using (FileStream stream = new FileStream(fullPath, mode, FileAccess.Write, FileShare.Read))
            {
                stream.Write(bytes, 0, bytes.Length);
                stream.Flush();
            }
            return ComputeSha256(bytes);
        }

        private static LoadedDeterministicScenario ParseInternal(string json, string sourcePath, string sourceSha256)
        {
            if (string.IsNullOrWhiteSpace(json)) throw new ScenarioJsonFormatException("Scenario JSON is empty", 0);
            ScenarioJsonShapeValidator.Validate(json);

            DeterministicScenarioDefinition definition;
            try { definition = JsonUtility.FromJson<DeterministicScenarioDefinition>(json); }
            catch (Exception exception)
            {
                throw new ScenarioJsonFormatException("Unity JSON deserialization failed: " + exception.Message, 0);
            }
            if (definition == null) throw new ScenarioJsonFormatException("Scenario JSON did not produce a definition", 0);
            ResolvedDeterministicScenario resolved = definition.Resolve();
            return new LoadedDeterministicScenario(sourcePath, sourceSha256, definition, resolved);
        }

        private static DeterministicScenarioDefinition BuildCanonicalDefinition(ResolvedDeterministicScenario scenario)
        {
            ScenarioAgentDefinition[] agents = new ScenarioAgentDefinition[scenario.Agents.Count];
            for (int index = 0; index < agents.Length; index++)
            {
                ResolvedScenarioAgent agent = scenario.Agents[index];
                agents[index] = new ScenarioAgentDefinition { agentId = agent.AgentId, start = agent.Start, goal = agent.Goal };
            }

            NavigationGridChange[] initial = new NavigationGridChange[scenario.InitialGridOverrides.Count];
            for (int index = 0; index < initial.Length; index++) initial[index] = scenario.InitialGridOverrides[index];

            ScheduledNavigationChangeDefinition[] scheduled = new ScheduledNavigationChangeDefinition[scenario.ScheduledChanges.Count];
            for (int index = 0; index < scheduled.Length; index++)
            {
                ResolvedScheduledNavigationChange source = scenario.ScheduledChanges[index];
                NavigationGridChange[] changes = new NavigationGridChange[source.Changes.Count];
                for (int changeIndex = 0; changeIndex < changes.Length; changeIndex++) changes[changeIndex] = source.Changes[changeIndex];
                scheduled[index] = new ScheduledNavigationChangeDefinition
                {
                    eventId = source.EventId,
                    simulationTick = source.SimulationTick,
                    order = source.Order,
                    repairBudgetMilliseconds = source.RepairBudgetMilliseconds,
                    changes = changes
                };
            }

            return new DeterministicScenarioDefinition
            {
                schemaVersion = scenario.SchemaVersion,
                scenarioId = scenario.ScenarioId,
                randomSeed = scenario.RandomSeed,
                gridWidth = scenario.GridWidth,
                gridHeight = scenario.GridHeight,
                defaultTraversalCost = scenario.DefaultTraversalCost,
                worldOrigin = scenario.WorldOrigin,
                cellSize = scenario.CellSize,
                connectivity = scenario.Connectivity,
                allowDiagonalCornerCutting = scenario.AllowDiagonalCornerCutting,
                fixedStepSeconds = scenario.FixedStepSeconds,
                maxSimulationTicks = scenario.MaxSimulationTicks,
                goalSetId = scenario.GoalSetId,
                initializationBudgetMilliseconds = scenario.InitializationBudgetMilliseconds,
                defaultPlanBudgetMilliseconds = scenario.DefaultPlanBudgetMilliseconds,
                defaultRepairBudgetMilliseconds = scenario.DefaultRepairBudgetMilliseconds,
                agents = agents,
                initialGridOverrides = initial,
                scheduledChanges = scheduled
            };
        }

        private static string DecodeUtf8(byte[] bytes)
        {
            try { return RemoveLeadingBom(StrictUtf8.GetString(bytes)); }
            catch (DecoderFallbackException exception) { throw new InvalidDataException("Scenario file is not valid UTF-8.", exception); }
        }

        private static string RemoveLeadingBom(string value)
        {
            return value.Length > 0 && value[0] == '\ufeff' ? value.Substring(1) : value;
        }

        private static string ComputeSha256(byte[] bytes)
        {
            using (SHA256 sha256 = SHA256.Create())
            {
                return BitConverter.ToString(sha256.ComputeHash(bytes)).Replace("-", string.Empty).ToLowerInvariant();
            }
        }

        private enum ObjectShape
        {
            Root,
            Vector3,
            Agent,
            Coordinate,
            GridChange,
            ScheduledChange
        }

        private sealed class ScenarioJsonShapeValidator
        {
            private readonly string json;
            private int index;

            private ScenarioJsonShapeValidator(string json)
            {
                this.json = json;
            }

            public static void Validate(string json)
            {
                ScenarioJsonShapeValidator parser = new ScenarioJsonShapeValidator(json);
                parser.SkipWhitespace();
                parser.ParseObject(ObjectShape.Root);
                parser.SkipWhitespace();
                if (!parser.AtEnd) parser.Fail("Unexpected content after the root object");
            }

            private bool AtEnd { get { return index >= json.Length; } }

            private void ParseObject(ObjectShape shape)
            {
                Expect('{');
                SkipWhitespace();
                HashSet<string> fields = new HashSet<string>(StringComparer.Ordinal);
                if (TryConsume('}'))
                {
                    ValidateRequiredFields(shape, fields);
                    return;
                }

                while (true)
                {
                    SkipWhitespace();
                    string field = ParseString();
                    if (!fields.Add(field)) Fail("Duplicate field '" + field + "'");
                    SkipWhitespace();
                    Expect(':');
                    SkipWhitespace();
                    ParseField(shape, field);
                    SkipWhitespace();
                    if (TryConsume('}')) break;
                    Expect(',');
                    SkipWhitespace();
                    if (!AtEnd && json[index] == '}') Fail("Trailing commas are not allowed");
                }

                ValidateRequiredFields(shape, fields);
            }

            private void ParseField(ObjectShape shape, string field)
            {
                switch (shape)
                {
                    case ObjectShape.Root:
                        ParseRootField(field);
                        return;
                    case ObjectShape.Vector3:
                        if (field == "x" || field == "y" || field == "z") { ParseFloatingNumber(); return; }
                        break;
                    case ObjectShape.Agent:
                        if (field == "agentId") { ParseInteger32(); return; }
                        if (field == "start" || field == "goal") { ParseObject(ObjectShape.Coordinate); return; }
                        break;
                    case ObjectShape.Coordinate:
                        if (field == "x" || field == "y") { ParseInteger32(); return; }
                        break;
                    case ObjectShape.GridChange:
                        if (field == "coordinate") { ParseObject(ObjectShape.Coordinate); return; }
                        if (field == "isWalkable") { ParseBoolean(); return; }
                        if (field == "traversalCost") { ParseFloatingNumber(); return; }
                        break;
                    case ObjectShape.ScheduledChange:
                        if (field == "eventId") { ParseNullableString(); return; }
                        if (field == "simulationTick") { ParseInteger64(); return; }
                        if (field == "order") { ParseInteger32(); return; }
                        if (field == "repairBudgetMilliseconds") { ParseFloatingNumber(); return; }
                        if (field == "changes") { ParseArray(ObjectShape.GridChange); return; }
                        break;
                }
                Fail("Unknown or misplaced field '" + field + "' in " + shape);
            }

            private void ParseRootField(string field)
            {
                switch (field)
                {
                    case "schemaVersion":
                    case "randomSeed":
                    case "gridWidth":
                    case "gridHeight":
                    case "connectivity":
                        ParseInteger32();
                        return;
                    case "maxSimulationTicks":
                        ParseInteger64();
                        return;
                    case "scenarioId":
                    case "goalSetId":
                        ParseNullableString();
                        return;
                    case "defaultTraversalCost":
                    case "cellSize":
                    case "fixedStepSeconds":
                    case "initializationBudgetMilliseconds":
                    case "defaultPlanBudgetMilliseconds":
                    case "defaultRepairBudgetMilliseconds":
                        ParseFloatingNumber();
                        return;
                    case "worldOrigin":
                        ParseObject(ObjectShape.Vector3);
                        return;
                    case "allowDiagonalCornerCutting":
                        ParseBoolean();
                        return;
                    case "agents":
                        ParseArray(ObjectShape.Agent);
                        return;
                    case "initialGridOverrides":
                        ParseArray(ObjectShape.GridChange);
                        return;
                    case "scheduledChanges":
                        ParseArray(ObjectShape.ScheduledChange);
                        return;
                    default:
                        Fail("Unknown root field '" + field + "'");
                        return;
                }
            }

            private void ParseArray(ObjectShape elementShape)
            {
                Expect('[');
                SkipWhitespace();
                if (TryConsume(']')) return;
                while (true)
                {
                    ParseObject(elementShape);
                    SkipWhitespace();
                    if (TryConsume(']')) return;
                    Expect(',');
                    SkipWhitespace();
                    if (!AtEnd && json[index] == ']') Fail("Trailing commas are not allowed");
                }
            }

            private void ParseNullableString()
            {
                if (!AtEnd && json[index] == '"') { ParseString(); return; }
                ExpectLiteral("null");
            }

            private string ParseString()
            {
                Expect('"');
                StringBuilder builder = new StringBuilder();
                while (!AtEnd)
                {
                    char character = json[index++];
                    if (character == '"') return builder.ToString();
                    if (character < 0x20) Fail("Unescaped control character in JSON string");
                    if (character != '\\')
                    {
                        builder.Append(character);
                        continue;
                    }

                    if (AtEnd) Fail("Incomplete JSON escape sequence");
                    char escape = json[index++];
                    switch (escape)
                    {
                        case '"': builder.Append('"'); break;
                        case '\\': builder.Append('\\'); break;
                        case '/': builder.Append('/'); break;
                        case 'b': builder.Append('\b'); break;
                        case 'f': builder.Append('\f'); break;
                        case 'n': builder.Append('\n'); break;
                        case 'r': builder.Append('\r'); break;
                        case 't': builder.Append('\t'); break;
                        case 'u': builder.Append(ParseUnicodeEscape()); break;
                        default: Fail("Invalid JSON escape sequence"); break;
                    }
                }
                Fail("Unterminated JSON string");
                return string.Empty;
            }

            private char ParseUnicodeEscape()
            {
                if (index + 4 > json.Length) Fail("Incomplete Unicode escape");
                int value = 0;
                for (int offset = 0; offset < 4; offset++)
                {
                    char character = json[index++];
                    int digit;
                    if (character >= '0' && character <= '9') digit = character - '0';
                    else if (character >= 'a' && character <= 'f') digit = character - 'a' + 10;
                    else if (character >= 'A' && character <= 'F') digit = character - 'A' + 10;
                    else { Fail("Invalid Unicode escape"); return '\0'; }
                    value = (value * 16) + digit;
                }
                return (char)value;
            }

            private void ParseBoolean()
            {
                if (MatchesLiteral("true")) ExpectLiteral("true");
                else ExpectLiteral("false");
            }

            private void ParseInteger32()
            {
                ParseNumber(true);
            }

            private void ParseInteger64()
            {
                ParseNumber(false);
            }

            private void ParseFloatingNumber()
            {
                ParseFiniteNumber();
            }

            private void ParseNumber(bool requireInt32)
            {
                int start = index;
                ParseNumberToken();
                string token = json.Substring(start, index - start);
                if (token.IndexOf('.') >= 0 || token.IndexOf('e') >= 0 || token.IndexOf('E') >= 0) Fail("This field requires an integer JSON token");
                long integerValue;
                if (!long.TryParse(token, NumberStyles.AllowLeadingSign, CultureInfo.InvariantCulture, out integerValue)) Fail("Integer is outside the Int64 range");
                if (requireInt32 && (integerValue < int.MinValue || integerValue > int.MaxValue)) Fail("Integer is outside the Int32 range");
            }

            private void ParseFiniteNumber()
            {
                int start = index;
                ParseNumberToken();
                string token = json.Substring(start, index - start);
                double numericValue;
                if (!double.TryParse(token, NumberStyles.Float, CultureInfo.InvariantCulture, out numericValue) || double.IsInfinity(numericValue)) Fail("Number is outside the finite Double range");
            }

            private void ParseNumberToken()
            {
                if (TryConsume('-') && AtEnd) Fail("Incomplete JSON number");
                if (TryConsume('0'))
                {
                    if (!AtEnd && IsDigit(json[index])) Fail("Leading zeros are not allowed in JSON numbers");
                }
                else
                {
                    if (AtEnd || json[index] < '1' || json[index] > '9') Fail("Invalid JSON number");
                    while (!AtEnd && IsDigit(json[index])) index++;
                }

                if (TryConsume('.'))
                {
                    if (AtEnd || !IsDigit(json[index])) Fail("A decimal point must be followed by digits");
                    while (!AtEnd && IsDigit(json[index])) index++;
                }
                if (!AtEnd && (json[index] == 'e' || json[index] == 'E'))
                {
                    index++;
                    if (!AtEnd && (json[index] == '+' || json[index] == '-')) index++;
                    if (AtEnd || !IsDigit(json[index])) Fail("A JSON exponent must contain digits");
                    while (!AtEnd && IsDigit(json[index])) index++;
                }
            }

            private void ValidateRequiredFields(ObjectShape shape, HashSet<string> fields)
            {
                string[] required;
                switch (shape)
                {
                    case ObjectShape.Root:
                        required = new[] { "schemaVersion", "scenarioId", "randomSeed", "gridWidth", "gridHeight", "defaultTraversalCost", "worldOrigin", "cellSize", "connectivity", "allowDiagonalCornerCutting", "fixedStepSeconds", "maxSimulationTicks", "goalSetId", "initializationBudgetMilliseconds", "defaultPlanBudgetMilliseconds", "defaultRepairBudgetMilliseconds", "agents", "initialGridOverrides", "scheduledChanges" };
                        break;
                    case ObjectShape.Vector3:
                        required = new[] { "x", "y", "z" };
                        break;
                    case ObjectShape.Agent:
                        required = new[] { "agentId", "start", "goal" };
                        break;
                    case ObjectShape.Coordinate:
                        required = new[] { "x", "y" };
                        break;
                    case ObjectShape.GridChange:
                        required = new[] { "coordinate", "isWalkable", "traversalCost" };
                        break;
                    case ObjectShape.ScheduledChange:
                        required = new[] { "eventId", "simulationTick", "order", "repairBudgetMilliseconds", "changes" };
                        break;
                    default:
                        throw new ArgumentOutOfRangeException("shape");
                }

                for (int fieldIndex = 0; fieldIndex < required.Length; fieldIndex++)
                {
                    if (!fields.Contains(required[fieldIndex])) Fail("Missing required field '" + required[fieldIndex] + "' in " + shape);
                }
            }

            private bool MatchesLiteral(string literal)
            {
                if (index + literal.Length > json.Length) return false;
                return string.CompareOrdinal(json, index, literal, 0, literal.Length) == 0;
            }

            private void ExpectLiteral(string literal)
            {
                if (!MatchesLiteral(literal)) Fail("Expected '" + literal + "'");
                index += literal.Length;
            }

            private void Expect(char expected)
            {
                if (AtEnd || json[index] != expected) Fail("Expected '" + expected + "'");
                index++;
            }

            private bool TryConsume(char value)
            {
                if (AtEnd || json[index] != value) return false;
                index++;
                return true;
            }

            private void SkipWhitespace()
            {
                while (!AtEnd)
                {
                    char character = json[index];
                    if (character != ' ' && character != '\t' && character != '\r' && character != '\n') return;
                    index++;
                }
            }

            private static bool IsDigit(char value)
            {
                return value >= '0' && value <= '9';
            }

            private void Fail(string message)
            {
                throw new ScenarioJsonFormatException(message, index);
            }
        }
    }
}

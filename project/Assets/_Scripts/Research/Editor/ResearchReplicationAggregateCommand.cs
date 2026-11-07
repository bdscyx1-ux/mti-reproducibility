using System;
using System.IO;
using System.Text;
using DDM.Research.Analysis;
using DDM.Research.Experiments;
using UnityEditor;
using UnityEngine;

namespace DDM.Research.Editor
{
    public static class ResearchReplicationAggregateCommand
    {
        private static readonly UTF8Encoding StrictUtf8 = new UTF8Encoding(false, true);

        public static void Run()
        {
            string[] arguments = Environment.GetCommandLineArgs();
            string requestPath = Path.GetFullPath(RequiredOption(arguments, "-ddmReplicationRequestPath"));
            string outputPath = Path.GetFullPath(RequiredOption(arguments, "-ddmAggregateOutputPath"));
            if (!File.Exists(requestPath)) throw new FileNotFoundException("Replication aggregation request was not found.", requestPath);
            if (File.Exists(outputPath)) throw new IOException("Replication aggregate output already exists: " + outputPath);

            PlanningReplicationAggregationRequest request = ReadJson<PlanningReplicationAggregationRequest>(requestPath);
            if (request == null || request.schemaVersion != PlanningReplicationAggregationRequest.CurrentSchemaVersion) throw new InvalidDataException("Unsupported replication aggregation request schema.");
            if (string.IsNullOrWhiteSpace(request.groupId)) throw new InvalidDataException("Replication group id is required.");
            if (string.IsNullOrWhiteSpace(request.algorithmId)) throw new InvalidDataException("Replication algorithm id is required.");
            if (request.workloadResultPaths == null || request.workloadResultPaths.Length < 2) throw new InvalidDataException("At least two workload result paths are required.");

            PlanningWorkloadResult[] runs = new PlanningWorkloadResult[request.workloadResultPaths.Length];
            for (int index = 0; index < runs.Length; index++)
            {
                string resultPath = Path.GetFullPath(request.workloadResultPaths[index]);
                if (!File.Exists(resultPath)) throw new FileNotFoundException("Workload result was not found.", resultPath);
                PlanningWorkloadResult result = ReadJson<PlanningWorkloadResult>(resultPath);
                if (result == null) throw new InvalidDataException("Workload result could not be deserialized: " + resultPath);
                if (!string.Equals(result.algorithmId, request.algorithmId, StringComparison.Ordinal)) throw new InvalidDataException("Workload algorithm does not match the aggregation request: " + resultPath);
                runs[index] = result;
            }

            PlanningReplicationAggregate aggregate = PlanningReplicationAggregator.Aggregate(
                request.groupId,
                request.scenarioSourceSha256,
                runs);
            string directory = Path.GetDirectoryName(outputPath);
            if (!string.IsNullOrEmpty(directory)) Directory.CreateDirectory(directory);
            WriteJsonCreateNew(outputPath, aggregate);
            Debug.Log("DDM replication aggregation completed. Output: " + outputPath);
        }

        private static T ReadJson<T>(string path)
        {
            string json;
            try { json = File.ReadAllText(path, StrictUtf8); }
            catch (DecoderFallbackException exception) { throw new InvalidDataException("JSON file is not valid UTF-8: " + path, exception); }
            try { return JsonUtility.FromJson<T>(json); }
            catch (Exception exception) { throw new InvalidDataException("JSON deserialization failed: " + path, exception); }
        }

        private static void WriteJsonCreateNew<T>(string path, T value)
        {
            string json = JsonUtility.ToJson(value, true).Replace("\r\n", "\n").Replace("\r", "\n");
            if (!json.EndsWith("\n", StringComparison.Ordinal)) json += "\n";
            byte[] bytes = StrictUtf8.GetBytes(json);
            using (FileStream stream = new FileStream(path, FileMode.CreateNew, FileAccess.Write, FileShare.Read))
            {
                stream.Write(bytes, 0, bytes.Length);
                stream.Flush();
            }
        }

        private static string RequiredOption(string[] arguments, string option)
        {
            string value = null;
            for (int index = 0; index < arguments.Length; index++)
            {
                if (!string.Equals(arguments[index], option, StringComparison.Ordinal)) continue;
                if (value != null) throw new ArgumentException("Command-line option was supplied more than once: " + option);
                if (index + 1 >= arguments.Length || string.IsNullOrWhiteSpace(arguments[index + 1])) throw new ArgumentException("Command-line option requires a value: " + option);
                value = arguments[index + 1];
            }
            if (value == null) throw new ArgumentException("Required command-line option is missing: " + option);
            return value;
        }
    }
}

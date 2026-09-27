using System;
using System.Collections.Generic;
using System.Text;
using System.Text.RegularExpressions;
using Microsoft.Windows.EventTracing;

namespace Kirakara.WindowsCompositorTrace
{
    public sealed class NativeStageEvent
    {
        public string Name { get; set; } = string.Empty;
        public double TimeMs { get; set; }
        public long Qpc { get; set; }
        public long Generation { get; set; }
        public long FrameId { get; set; }
        public int ThreadId { get; set; }
    }

    public sealed class DxgPresentEvent
    {
        public double TimeMs { get; set; }
        public int ThreadId { get; set; }
        public uint Context { get; set; }
        public ulong Hwnd { get; set; }
        public uint VidPnSourceId { get; set; }
        public int FlipInterval { get; set; }
        public uint Flags { get; set; }
        public int ReturnStatus { get; set; }
        public ulong SourceAllocation { get; set; }
        public ulong DestinationAllocation { get; set; }
    }

    public sealed class DecoderResult
    {
        public long NativeStageProviderEvents { get; set; }
        public long DxgKrnlProviderEvents { get; set; }
        public long MalformedNativeStageEvents { get; set; }
        public long MalformedDxgPresentEvents { get; set; }
        public List<NativeStageEvent> NativeStageEvents { get; } =
            new List<NativeStageEvent>();
        public List<DxgPresentEvent> DxgPresentEvents { get; } =
            new List<DxgPresentEvent>();
    }

    public static class CompositorTraceDecoder
    {
        private static readonly Guid NativeStageProvider =
            new Guid("9b2572f2-7f04-4059-9e9c-fcbafbf5b0de");
        private static readonly Guid DxgKrnlProvider =
            new Guid("802ec45a-1e99-4b83-9920-87c98277ba9d");

        private static readonly Regex NativeStagePattern = new Regex(
            @"^(?<name>StagePublish|PreviewPublication|PreviewCallback) " +
            @"qpc=(?<qpc>\d+) generation=(?<generation>\d+) " +
            @"frame_id=(?<frame>\d+) thread_id=(?<thread>\d+)$",
            RegexOptions.Compiled | RegexOptions.CultureInvariant);

        private static uint ReadUInt32(ReadOnlySpan<byte> data, int offset)
        {
            return (uint)(data[offset]
                | (data[offset + 1] << 8)
                | (data[offset + 2] << 16)
                | (data[offset + 3] << 24));
        }

        private static ulong ReadUInt64(ReadOnlySpan<byte> data, int offset)
        {
            return (ulong)ReadUInt32(data, offset)
                | ((ulong)ReadUInt32(data, offset + 4) << 32);
        }

        public static DecoderResult Run(
            string etlPath,
            int processId,
            string toolkitPath,
            string catalogPath)
        {
            var result = new DecoderResult();
            var settings = new TraceProcessorSettings
            {
                ToolkitPath = toolkitPath,
                CatalogPath = catalogPath,
                SuppressFirstTimeSetupMessage = true,
                AllowLostEvents = false,
            };

            using (ITraceProcessor processor =
                TraceProcessor.Create(etlPath, settings))
            {
                IStreamingTraceSource stream = processor.UseStreaming();
                stream.UseUnparsedEvents(
                    new[] { NativeStageProvider, DxgKrnlProvider },
                    context =>
                    {
                        TraceEvent traceEvent = context.Event;
                        if (traceEvent.ProviderId == NativeStageProvider)
                        {
                            result.NativeStageProviderEvents++;
                            DecodeNativeStageEvent(traceEvent, processId, result);
                            return;
                        }

                        result.DxgKrnlProviderEvents++;
                        DecodeDxgPresentEvent(traceEvent, processId, result);
                    });
                processor.Process();
            }

            return result;
        }

        private static void DecodeNativeStageEvent(
            TraceEvent traceEvent,
            int processId,
            DecoderResult result)
        {
            if (traceEvent.ProcessId != processId)
            {
                return;
            }

            string payload = Encoding.Unicode
                .GetString(traceEvent.Data.ToArray())
                .TrimEnd('\0');
            Match match = NativeStagePattern.Match(payload);
            if (!match.Success)
            {
                result.MalformedNativeStageEvents++;
                return;
            }

            result.NativeStageEvents.Add(new NativeStageEvent
            {
                Name = match.Groups["name"].Value,
                TimeMs = (double)traceEvent.Timestamp.TotalMilliseconds,
                Qpc = long.Parse(match.Groups["qpc"].Value),
                Generation = long.Parse(match.Groups["generation"].Value),
                FrameId = long.Parse(match.Groups["frame"].Value),
                ThreadId = int.Parse(match.Groups["thread"].Value),
            });
        }

        private static void DecodeDxgPresentEvent(
            TraceEvent traceEvent,
            int processId,
            DecoderResult result)
        {
            // Microsoft-Windows-DxgKrnl/Present/win:Info on the Windows 11
            // baseline. Other event versions are deliberately not guessed.
            if (traceEvent.ProcessId != processId
                || traceEvent.Id != 184
                || traceEvent.Version != 1)
            {
                return;
            }

            ReadOnlySpan<byte> data = traceEvent.Data;
            if (data.Length < 44)
            {
                result.MalformedDxgPresentEvents++;
                return;
            }

            result.DxgPresentEvents.Add(new DxgPresentEvent
            {
                TimeMs = (double)traceEvent.Timestamp.TotalMilliseconds,
                ThreadId = traceEvent.ThreadId ?? -1,
                Context = ReadUInt32(data, 0),
                Hwnd = ReadUInt64(data, 4),
                VidPnSourceId = ReadUInt32(data, 12),
                FlipInterval = unchecked((int)ReadUInt32(data, 16)),
                Flags = ReadUInt32(data, 20),
                ReturnStatus = unchecked((int)ReadUInt32(data, 24)),
                SourceAllocation = ReadUInt64(data, 28),
                DestinationAllocation = ReadUInt64(data, 36),
            });
        }
    }
}

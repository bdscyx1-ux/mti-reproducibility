#include <IUnityInterface.h>
#include <IUnityProfiler.h>
#include <IUnityProfilerCallbacks.h>

#include <Windows.h>

#include <atomic>
#include <cstdint>
#include <cstring>
#include <limits>
#include <thread>

namespace
{
    IUnityProfilerCallbacks* g_callbacks = nullptr;
    std::atomic<const UnityProfilerMarkerDesc*> g_gcAllocMarker(nullptr);
    std::atomic<int> g_createCallbackRegistrationCode(std::numeric_limits<int>::min());
    std::atomic<int> g_markerCallbackRegistrationCode(std::numeric_limits<int>::min());
    std::atomic<int> g_markerSeen(0);
    std::atomic<int> g_markerRegistered(0);
    std::atomic<int> g_active(0);
    std::atomic<uint32_t> g_ownerThreadId(0);
    std::atomic<uint32_t> g_inFlight(0);
    std::atomic<uint64_t> g_ownerObservationCount(0);
    std::atomic<uint64_t> g_foreignObservationCount(0);
    std::atomic<int> g_lastEventType(-1);
    std::atomic<uint32_t> g_lastEventDataCount(0);
    std::atomic<uint32_t> g_lastMetadataType(0);
    std::atomic<uint32_t> g_lastMetadataSize(0);
    std::atomic<int> g_lastPointerNonNull(0);
    std::atomic<int> g_lastRawInt64Available(0);
    std::atomic<int64_t> g_lastRawInt64(0);

    bool IsReadyInternal()
    {
        return g_callbacks != nullptr &&
            g_createCallbackRegistrationCode.load(std::memory_order_acquire) == 0 &&
            g_markerSeen.load(std::memory_order_acquire) == 1 &&
            g_markerRegistered.load(std::memory_order_acquire) == 1 &&
            g_markerCallbackRegistrationCode.load(std::memory_order_acquire) == 0;
    }

    void UNITY_INTERFACE_API OnProbeEvent(
        const UnityProfilerMarkerDesc*,
        UnityProfilerMarkerEventType eventType,
        uint16_t eventDataCount,
        const UnityProfilerMarkerData* eventData,
        void*)
    {
        if (g_active.load(std::memory_order_acquire) != 1)
            return;

        g_inFlight.fetch_add(1, std::memory_order_acq_rel);
        if (g_active.load(std::memory_order_acquire) != 1)
        {
            g_inFlight.fetch_sub(1, std::memory_order_acq_rel);
            return;
        }

        if (static_cast<uint32_t>(::GetCurrentThreadId()) != g_ownerThreadId.load(std::memory_order_acquire))
        {
            g_foreignObservationCount.fetch_add(1, std::memory_order_relaxed);
            g_inFlight.fetch_sub(1, std::memory_order_acq_rel);
            return;
        }

        g_ownerObservationCount.fetch_add(1, std::memory_order_relaxed);
        g_lastEventType.store(static_cast<int>(eventType), std::memory_order_release);
        g_lastEventDataCount.store(static_cast<uint32_t>(eventDataCount), std::memory_order_release);
        if (eventDataCount > 0 && eventData != nullptr)
        {
            g_lastMetadataType.store(static_cast<uint32_t>(eventData[0].type), std::memory_order_release);
            g_lastMetadataSize.store(eventData[0].size, std::memory_order_release);
            g_lastPointerNonNull.store(eventData[0].ptr == nullptr ? 0 : 1, std::memory_order_release);
            if (eventData[0].type == kUnityProfilerMarkerDataTypeInt64 && eventData[0].ptr != nullptr)
            {
                int64_t value = 0;
                std::memcpy(&value, eventData[0].ptr, sizeof(value));
                g_lastRawInt64.store(value, std::memory_order_release);
                g_lastRawInt64Available.store(1, std::memory_order_release);
            }
        }
        g_inFlight.fetch_sub(1, std::memory_order_acq_rel);
    }

    void UNITY_INTERFACE_API OnMarkerCreated(const UnityProfilerMarkerDesc* markerDesc, void*)
    {
        if (markerDesc == nullptr || markerDesc->name == nullptr || std::strcmp(markerDesc->name, "GC.Alloc") != 0)
            return;

        int expected = 0;
        if (!g_markerSeen.compare_exchange_strong(expected, 1, std::memory_order_acq_rel))
            return;

        g_gcAllocMarker.store(markerDesc, std::memory_order_release);
        const int code = g_callbacks == nullptr
            ? -1
            : g_callbacks->RegisterMarkerEventCallback(markerDesc, &OnProbeEvent, nullptr);
        g_markerCallbackRegistrationCode.store(code, std::memory_order_release);
        g_markerRegistered.store(code == 0 ? 1 : 0, std::memory_order_release);
    }
}

extern "C" void UNITY_INTERFACE_EXPORT UNITY_INTERFACE_API UnityPluginLoad(IUnityInterfaces* unityInterfaces)
{
    if (unityInterfaces == nullptr)
    {
        g_createCallbackRegistrationCode.store(-1, std::memory_order_release);
        return;
    }
    g_callbacks = unityInterfaces->Get<IUnityProfilerCallbacks>();
    if (g_callbacks == nullptr)
    {
        g_createCallbackRegistrationCode.store(-2, std::memory_order_release);
        return;
    }
    const int code = g_callbacks->RegisterCreateMarkerCallback(&OnMarkerCreated, nullptr);
    g_createCallbackRegistrationCode.store(code, std::memory_order_release);
}

extern "C" void UNITY_INTERFACE_EXPORT UNITY_INTERFACE_API UnityPluginUnload()
{
    g_active.store(0, std::memory_order_release);
    while (g_inFlight.load(std::memory_order_acquire) != 0)
        std::this_thread::yield();
    if (g_callbacks != nullptr)
    {
        if (g_markerRegistered.load(std::memory_order_acquire) == 1)
            g_callbacks->UnregisterMarkerEventCallback(g_gcAllocMarker.load(std::memory_order_acquire), &OnProbeEvent, nullptr);
        g_callbacks->UnregisterCreateMarkerCallback(&OnMarkerCreated, nullptr);
    }
    g_callbacks = nullptr;
    g_gcAllocMarker.store(nullptr, std::memory_order_release);
    g_markerRegistered.store(0, std::memory_order_release);
}

extern "C" UNITY_INTERFACE_EXPORT int UNITY_INTERFACE_API Gate14ReMED3V3Probe_IsReady()
{
    return IsReadyInternal() ? 1 : 0;
}

extern "C" UNITY_INTERFACE_EXPORT int UNITY_INTERFACE_API Gate14ReMED3V3Probe_GetMarkerSeen()
{
    return g_markerSeen.load(std::memory_order_acquire);
}

extern "C" UNITY_INTERFACE_EXPORT int UNITY_INTERFACE_API Gate14ReMED3V3Probe_GetCreateCallbackRegistrationCode()
{
    return g_createCallbackRegistrationCode.load(std::memory_order_acquire);
}

extern "C" UNITY_INTERFACE_EXPORT int UNITY_INTERFACE_API Gate14ReMED3V3Probe_GetMarkerCallbackRegistrationCode()
{
    return g_markerCallbackRegistrationCode.load(std::memory_order_acquire);
}

extern "C" UNITY_INTERFACE_EXPORT int UNITY_INTERFACE_API Gate14ReMED3V3Probe_Begin()
{
    if (!IsReadyInternal())
        return 10;
    int expected = 0;
    if (!g_active.compare_exchange_strong(expected, 2, std::memory_order_acq_rel))
        return 11;
    g_ownerThreadId.store(static_cast<uint32_t>(::GetCurrentThreadId()), std::memory_order_release);
    g_ownerObservationCount.store(0, std::memory_order_release);
    g_foreignObservationCount.store(0, std::memory_order_release);
    g_lastEventType.store(-1, std::memory_order_release);
    g_lastEventDataCount.store(0, std::memory_order_release);
    g_lastMetadataType.store(0, std::memory_order_release);
    g_lastMetadataSize.store(0, std::memory_order_release);
    g_lastPointerNonNull.store(0, std::memory_order_release);
    g_lastRawInt64Available.store(0, std::memory_order_release);
    g_lastRawInt64.store(0, std::memory_order_release);
    g_active.store(1, std::memory_order_release);
    return 0;
}

extern "C" UNITY_INTERFACE_EXPORT int UNITY_INTERFACE_API Gate14ReMED3V3Probe_End(
    uint64_t* ownerObservationCount,
    uint64_t* foreignObservationCount,
    int* lastEventType,
    uint32_t* lastEventDataCount,
    uint32_t* lastMetadataType,
    uint32_t* lastMetadataSize,
    int* lastPointerNonNull,
    int* lastRawInt64Available,
    int64_t* lastRawInt64,
    uint32_t* ownerThreadId)
{
    if (ownerObservationCount == nullptr || foreignObservationCount == nullptr || lastEventType == nullptr ||
        lastEventDataCount == nullptr || lastMetadataType == nullptr || lastMetadataSize == nullptr ||
        lastPointerNonNull == nullptr || lastRawInt64Available == nullptr || lastRawInt64 == nullptr ||
        ownerThreadId == nullptr)
        return 20;
    if (static_cast<uint32_t>(::GetCurrentThreadId()) != g_ownerThreadId.load(std::memory_order_acquire))
        return 13;
    int expected = 1;
    if (!g_active.compare_exchange_strong(expected, 2, std::memory_order_acq_rel))
        return 12;
    while (g_inFlight.load(std::memory_order_acquire) != 0)
        std::this_thread::yield();
    *ownerObservationCount = g_ownerObservationCount.load(std::memory_order_acquire);
    *foreignObservationCount = g_foreignObservationCount.load(std::memory_order_acquire);
    *lastEventType = g_lastEventType.load(std::memory_order_acquire);
    *lastEventDataCount = g_lastEventDataCount.load(std::memory_order_acquire);
    *lastMetadataType = g_lastMetadataType.load(std::memory_order_acquire);
    *lastMetadataSize = g_lastMetadataSize.load(std::memory_order_acquire);
    *lastPointerNonNull = g_lastPointerNonNull.load(std::memory_order_acquire);
    *lastRawInt64Available = g_lastRawInt64Available.load(std::memory_order_acquire);
    *lastRawInt64 = g_lastRawInt64.load(std::memory_order_acquire);
    *ownerThreadId = g_ownerThreadId.load(std::memory_order_acquire);
    g_active.store(0, std::memory_order_release);
    return 0;
}

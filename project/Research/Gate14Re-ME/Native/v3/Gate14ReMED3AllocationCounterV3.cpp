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

    // 0 = idle, 1 = arming, 2 = active, 3 = closing.
    std::atomic<int> g_windowState(0);
    std::atomic<uint32_t> g_ownerThreadId(0);
    std::atomic<uint64_t> g_ownerBytes(0);
    std::atomic<uint64_t> g_ownerEvents(0);
    std::atomic<uint64_t> g_foreignBytes(0);
    std::atomic<uint64_t> g_foreignEvents(0);
    std::atomic<uint64_t> g_invalidMetadataEvents(0);
    std::atomic<uint64_t> g_overflowEvents(0);
    std::atomic<uint32_t> g_inFlightCallbacks(0);

    bool AddChecked(std::atomic<uint64_t>& target, uint64_t value)
    {
        const uint64_t previous = target.fetch_add(value, std::memory_order_relaxed);
        if (previous > static_cast<uint64_t>(std::numeric_limits<int64_t>::max()) - value)
        {
            g_overflowEvents.fetch_add(1, std::memory_order_relaxed);
            return false;
        }
        return true;
    }

    void UNITY_INTERFACE_API OnGCAllocEvent(
        const UnityProfilerMarkerDesc*,
        UnityProfilerMarkerEventType eventType,
        uint16_t eventDataCount,
        const UnityProfilerMarkerData* eventData,
        void*)
    {
        if (g_windowState.load(std::memory_order_acquire) != 2)
            return;

        g_inFlightCallbacks.fetch_add(1, std::memory_order_acq_rel);
        if (g_windowState.load(std::memory_order_acquire) != 2)
        {
            g_inFlightCallbacks.fetch_sub(1, std::memory_order_acq_rel);
            return;
        }

        if (eventType == kUnityProfilerMarkerEventTypeEnd)
        {
            g_inFlightCallbacks.fetch_sub(1, std::memory_order_acq_rel);
            return;
        }

        if ((eventType != kUnityProfilerMarkerEventTypeBegin && eventType != kUnityProfilerMarkerEventTypeSingle) ||
            eventDataCount < 1 ||
            eventData == nullptr ||
            eventData[0].type != kUnityProfilerMarkerDataTypeInt64 ||
            eventData[0].size != sizeof(int64_t) ||
            eventData[0].ptr == nullptr)
        {
            g_invalidMetadataEvents.fetch_add(1, std::memory_order_relaxed);
            g_inFlightCallbacks.fetch_sub(1, std::memory_order_acq_rel);
            return;
        }

        int64_t signedSize = 0;
        std::memcpy(&signedSize, eventData[0].ptr, sizeof(signedSize));
        if (signedSize <= 0)
        {
            g_invalidMetadataEvents.fetch_add(1, std::memory_order_relaxed);
            g_inFlightCallbacks.fetch_sub(1, std::memory_order_acq_rel);
            return;
        }

        const uint64_t size = static_cast<uint64_t>(signedSize);
        const uint32_t currentThreadId = static_cast<uint32_t>(::GetCurrentThreadId());
        if (currentThreadId == g_ownerThreadId.load(std::memory_order_acquire))
        {
            AddChecked(g_ownerBytes, size);
            AddChecked(g_ownerEvents, 1);
        }
        else
        {
            AddChecked(g_foreignBytes, size);
            AddChecked(g_foreignEvents, 1);
        }

        g_inFlightCallbacks.fetch_sub(1, std::memory_order_acq_rel);
    }

    void UNITY_INTERFACE_API OnMarkerCreated(const UnityProfilerMarkerDesc* markerDesc, void*)
    {
        if (markerDesc == nullptr || markerDesc->name == nullptr || std::strcmp(markerDesc->name, "GC.Alloc") != 0)
            return;

        int expected = 0;
        if (!g_markerSeen.compare_exchange_strong(expected, 1, std::memory_order_acq_rel))
            return;

        g_gcAllocMarker.store(markerDesc, std::memory_order_release);
        const int registrationCode = g_callbacks == nullptr
            ? -1
            : g_callbacks->RegisterMarkerEventCallback(markerDesc, &OnGCAllocEvent, nullptr);
        g_markerCallbackRegistrationCode.store(registrationCode, std::memory_order_release);
        g_markerRegistered.store(registrationCode == 0 ? 1 : 0, std::memory_order_release);
    }

    bool IsReadyInternal()
    {
        return g_callbacks != nullptr &&
            g_createCallbackRegistrationCode.load(std::memory_order_acquire) == 0 &&
            g_markerSeen.load(std::memory_order_acquire) == 1 &&
            g_markerRegistered.load(std::memory_order_acquire) == 1 &&
            g_markerCallbackRegistrationCode.load(std::memory_order_acquire) == 0;
    }

    int CopyCounters(
        int64_t* ownerBytes,
        int64_t* ownerEvents,
        int64_t* foreignBytes,
        int64_t* foreignEvents,
        int64_t* invalidMetadataEvents,
        int64_t* overflowEvents,
        uint32_t* ownerThreadId)
    {
        if (ownerBytes == nullptr || ownerEvents == nullptr || foreignBytes == nullptr ||
            foreignEvents == nullptr || invalidMetadataEvents == nullptr || overflowEvents == nullptr ||
            ownerThreadId == nullptr)
            return 20;

        const uint64_t ownerBytesValue = g_ownerBytes.load(std::memory_order_acquire);
        const uint64_t ownerEventsValue = g_ownerEvents.load(std::memory_order_acquire);
        const uint64_t foreignBytesValue = g_foreignBytes.load(std::memory_order_acquire);
        const uint64_t foreignEventsValue = g_foreignEvents.load(std::memory_order_acquire);
        const uint64_t invalidValue = g_invalidMetadataEvents.load(std::memory_order_acquire);
        const uint64_t overflowValue = g_overflowEvents.load(std::memory_order_acquire);
        if (ownerBytesValue > static_cast<uint64_t>(std::numeric_limits<int64_t>::max()) ||
            ownerEventsValue > static_cast<uint64_t>(std::numeric_limits<int64_t>::max()) ||
            foreignBytesValue > static_cast<uint64_t>(std::numeric_limits<int64_t>::max()) ||
            foreignEventsValue > static_cast<uint64_t>(std::numeric_limits<int64_t>::max()) ||
            invalidValue > static_cast<uint64_t>(std::numeric_limits<int64_t>::max()) ||
            overflowValue > static_cast<uint64_t>(std::numeric_limits<int64_t>::max()))
            return 21;

        *ownerBytes = static_cast<int64_t>(ownerBytesValue);
        *ownerEvents = static_cast<int64_t>(ownerEventsValue);
        *foreignBytes = static_cast<int64_t>(foreignBytesValue);
        *foreignEvents = static_cast<int64_t>(foreignEventsValue);
        *invalidMetadataEvents = static_cast<int64_t>(invalidValue);
        *overflowEvents = static_cast<int64_t>(overflowValue);
        *ownerThreadId = g_ownerThreadId.load(std::memory_order_acquire);
        return 0;
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

    const int registrationCode = g_callbacks->RegisterCreateMarkerCallback(&OnMarkerCreated, nullptr);
    g_createCallbackRegistrationCode.store(registrationCode, std::memory_order_release);
}

extern "C" void UNITY_INTERFACE_EXPORT UNITY_INTERFACE_API UnityPluginUnload()
{
    g_windowState.store(3, std::memory_order_release);
    while (g_inFlightCallbacks.load(std::memory_order_acquire) != 0)
        std::this_thread::yield();

    if (g_callbacks != nullptr)
    {
        if (g_markerRegistered.load(std::memory_order_acquire) == 1)
            g_callbacks->UnregisterMarkerEventCallback(g_gcAllocMarker.load(std::memory_order_acquire), &OnGCAllocEvent, nullptr);
        g_callbacks->UnregisterCreateMarkerCallback(&OnMarkerCreated, nullptr);
    }

    g_callbacks = nullptr;
    g_gcAllocMarker.store(nullptr, std::memory_order_release);
    g_markerRegistered.store(0, std::memory_order_release);
    g_windowState.store(0, std::memory_order_release);
}

extern "C" UNITY_INTERFACE_EXPORT int UNITY_INTERFACE_API Gate14ReMED3V3_IsReady()
{
    return IsReadyInternal() ? 1 : 0;
}

extern "C" UNITY_INTERFACE_EXPORT int UNITY_INTERFACE_API Gate14ReMED3V3_GetMarkerSeen()
{
    return g_markerSeen.load(std::memory_order_acquire);
}

extern "C" UNITY_INTERFACE_EXPORT int UNITY_INTERFACE_API Gate14ReMED3V3_GetCreateCallbackRegistrationCode()
{
    return g_createCallbackRegistrationCode.load(std::memory_order_acquire);
}

extern "C" UNITY_INTERFACE_EXPORT int UNITY_INTERFACE_API Gate14ReMED3V3_GetMarkerCallbackRegistrationCode()
{
    return g_markerCallbackRegistrationCode.load(std::memory_order_acquire);
}

extern "C" UNITY_INTERFACE_EXPORT uint32_t UNITY_INTERFACE_API Gate14ReMED3V3_GetCurrentNativeThreadId()
{
    return static_cast<uint32_t>(::GetCurrentThreadId());
}

extern "C" UNITY_INTERFACE_EXPORT int UNITY_INTERFACE_API Gate14ReMED3V3_BeginWindow()
{
    if (!IsReadyInternal())
        return 10;

    int expected = 0;
    if (!g_windowState.compare_exchange_strong(expected, 1, std::memory_order_acq_rel))
        return 11;

    g_ownerBytes.store(0, std::memory_order_release);
    g_ownerEvents.store(0, std::memory_order_release);
    g_foreignBytes.store(0, std::memory_order_release);
    g_foreignEvents.store(0, std::memory_order_release);
    g_invalidMetadataEvents.store(0, std::memory_order_release);
    g_overflowEvents.store(0, std::memory_order_release);
    g_ownerThreadId.store(static_cast<uint32_t>(::GetCurrentThreadId()), std::memory_order_release);
    g_windowState.store(2, std::memory_order_release);
    return 0;
}

extern "C" UNITY_INTERFACE_EXPORT int UNITY_INTERFACE_API Gate14ReMED3V3_SnapshotWindow(
    int64_t* ownerBytes,
    int64_t* ownerEvents,
    int64_t* foreignBytes,
    int64_t* foreignEvents,
    int64_t* invalidMetadataEvents,
    int64_t* overflowEvents,
    uint32_t* ownerThreadId)
{
    if (g_windowState.load(std::memory_order_acquire) != 2)
        return 12;
    if (static_cast<uint32_t>(::GetCurrentThreadId()) != g_ownerThreadId.load(std::memory_order_acquire))
        return 13;
    return CopyCounters(ownerBytes, ownerEvents, foreignBytes, foreignEvents, invalidMetadataEvents, overflowEvents, ownerThreadId);
}

extern "C" UNITY_INTERFACE_EXPORT int UNITY_INTERFACE_API Gate14ReMED3V3_EndWindow(
    int64_t* ownerBytes,
    int64_t* ownerEvents,
    int64_t* foreignBytes,
    int64_t* foreignEvents,
    int64_t* invalidMetadataEvents,
    int64_t* overflowEvents,
    uint32_t* ownerThreadId)
{
    if (static_cast<uint32_t>(::GetCurrentThreadId()) != g_ownerThreadId.load(std::memory_order_acquire))
        return 13;

    int expected = 2;
    if (!g_windowState.compare_exchange_strong(expected, 3, std::memory_order_acq_rel))
        return 12;

    while (g_inFlightCallbacks.load(std::memory_order_acquire) != 0)
        std::this_thread::yield();

    const int copyCode = CopyCounters(ownerBytes, ownerEvents, foreignBytes, foreignEvents,
        invalidMetadataEvents, overflowEvents, ownerThreadId);
    g_windowState.store(0, std::memory_order_release);
    return copyCode;
}
